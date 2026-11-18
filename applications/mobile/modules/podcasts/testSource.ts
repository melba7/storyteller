// LOFI-FORK: the podcasts section's tests (see FORK.md).
//
// Reads the source of a screen and answers questions about it, for the tests that guard a
// rule about components (a row reads no whole store, a list keeps its render function). It
// looks at the parsed code, not at the text, so a comment never counts and a renamed import,
// a re-export or a wrapper in the same file cannot hide a name. Only tests import this.
import { readFileSync } from "node:fs"
import { createRequire } from "node:module"
import { resolve } from "node:path"

/** A node of the syntax tree: every one has a type, the rest depends on the type. */
type Node = { type: string; [key: string]: unknown }

// Babel's parser ships no types here, so it is loaded without them.
const require = createRequire(import.meta.url)
const parser = require("@babel/parser") as {
  parse(code: string, options: object): { program: Node }
}

const ROOT = resolve(__dirname, "../..")
const OPTIONS = { sourceType: "module", plugins: ["typescript", "jsx"] }
// Keys that hold positions or comments, never code.
const SKIPPED = new Set([
  "loc",
  "start",
  "end",
  "extra",
  "comments",
  "leadingComments",
  "trailingComments",
  "innerComments",
])
const FUNCTIONS = new Set([
  "FunctionDeclaration",
  "FunctionExpression",
  "ArrowFunctionExpression",
  "ObjectMethod",
  "ClassMethod",
])

/** A file's text, from its path inside `applications/mobile` ("podcasts/EpisodeRow.tsx"). */
export function readSource(path: string): string {
  return readFileSync(resolve(ROOT, path), "utf8")
}

function isNode(value: unknown): value is Node {
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as { type?: unknown }).type === "string"
  )
}

/** Calls `visit` on every node of the tree, with how many functions the node sits inside. */
function walk(
  node: unknown,
  visit: (node: Node, depth: number) => void,
  depth = 0,
) {
  if (Array.isArray(node)) {
    for (const child of node) walk(child, visit, depth)
    return
  }
  if (!isNode(node)) return
  visit(node, depth)
  const inner = FUNCTIONS.has(node.type) ? depth + 1 : depth
  for (const [key, value] of Object.entries(node)) {
    if (!SKIPPED.has(key)) walk(value, visit, inner)
  }
}

function programOf(source: string): Node {
  return parser.parse(source, OPTIONS).program
}

function nameOf(value: unknown): string {
  if (!isNode(value)) return ""
  if (value.type === "Identifier") return String(value["name"])
  if (value.type === "StringLiteral") return String(value["value"])
  return ""
}

/**
 * The names from `forbidden` that the source mentions in any role: imported (under its own
 * name or another), re-exported, called, read from a namespace (`store.usePlayer`), looked up
 * by a string, or wrapped by a function of the same file. `"export *"` is listed for a star
 * re-export, which can carry any name. Comments are not code and never count.
 */
export function mentionsOf(
  source: string,
  forbidden: readonly string[],
): string[] {
  const found = new Set<string>()
  walk(programOf(source), (node) => {
    if (node.type === "ExportAllDeclaration") found.add("export *")
    const name = mentionedName(node)
    if (forbidden.includes(name)) found.add(name)
  })
  return [...found].sort()
}

/** The name a node spells, when it spells one: an identifier, a tag, or a string. */
function mentionedName(node: Node): string {
  switch (node.type) {
    case "Identifier":
    case "JSXIdentifier":
      return String(node["name"])
    case "StringLiteral":
      return String(node["value"])
    case "TemplateElement":
      return String((node["value"] as { cooked?: string | null }).cooked ?? "")
    default:
      return ""
  }
}

export type Import = { local: string; imported: string; from: string }

/** What the source imports: the local name, the name in the other file, and that file. */
export function importsOf(source: string): Import[] {
  const out: Import[] = []
  for (const node of programOf(source)["body"] as Node[]) {
    if (node.type !== "ImportDeclaration") continue
    const from = nameOf(node["source"])
    for (const s of node["specifiers"] as Node[]) {
      out.push({
        local: nameOf(s["local"]),
        imported:
          s.type === "ImportSpecifier"
            ? nameOf(s["imported"])
            : s.type === "ImportDefaultSpecifier"
              ? "default"
              : "*",
        from,
      })
    }
  }
  return out
}

/** The names the source exports with a declaration (`export function X`, `export const X`). */
export function exportedNames(source: string): string[] {
  const names: string[] = []
  for (const node of programOf(source)["body"] as Node[]) {
    if (node.type !== "ExportNamedDeclaration") continue
    const declaration = node["declaration"]
    if (!isNode(declaration)) continue
    if (declaration.type === "VariableDeclaration") {
      for (const d of declaration["declarations"] as Node[]) {
        names.push(nameOf(d["id"]))
      }
    } else {
      names.push(nameOf(declaration["id"]))
    }
  }
  return names
}

export type Call = {
  /** The name the callee has in the other file ("memo" for `import { memo as m }`). */
  callee: string
  /** The file the callee is imported from, or "" when it is not imported. */
  from: string
  /** What is passed to it, as source text of each argument's kind (Identifier, Arrow...). */
  args: string[]
}

/** `export const name = callee(...)`: what is called and with what, or null when it isn't. */
export function exportedCall(source: string, name: string): Call | null {
  const imports = importsOf(source)
  for (const node of programOf(source)["body"] as Node[]) {
    if (node.type !== "ExportNamedDeclaration") continue
    const declaration = node["declaration"]
    if (!isNode(declaration) || declaration.type !== "VariableDeclaration") {
      continue
    }
    for (const d of declaration["declarations"] as Node[]) {
      const init = d["init"]
      if (nameOf(d["id"]) !== name || !isNode(init)) continue
      if (init.type !== "CallExpression") return null
      const callee = init["callee"] as Node
      // `memo(...)` and `React.memo(...)` are both a call of memo.
      const local =
        callee.type === "MemberExpression" ? callee["object"] : callee
      const property =
        callee.type === "MemberExpression" ? nameOf(callee["property"]) : ""
      const imported = imports.find((i) => i.local === nameOf(local))
      return {
        callee: property || imported?.imported || nameOf(local),
        from: imported?.from ?? "",
        args: (init["arguments"] as Node[]).map((a) =>
          a.type === "Identifier" ? nameOf(a) : a.type,
        ),
      }
    }
  }
  return null
}

/**
 * How many functions each call of `name` sits inside. The body of a component is 1, so a
 * call in one of its handlers (`onPress={() => ...}`) is 2 or more.
 */
export function callDepths(source: string, name: string): number[] {
  const depths: number[] = []
  walk(programOf(source), (node, depth) => {
    if (node.type === "CallExpression" && nameOf(node["callee"]) === name) {
      depths.push(depth)
    }
  })
  return depths
}
