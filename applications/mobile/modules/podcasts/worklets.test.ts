// LOFI-FORK: guards the podcasts section against worklets that call plain functions.
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs"
import { createRequire } from "node:module"
import { dirname, join, resolve } from "node:path"

import { describe, expect, it } from "vitest"

/*
 * A worklet (a gesture callback, `useAnimatedStyle` and so on) runs on the UI thread. There it
 * may call only other worklets: calling a plain function throws "Tried to synchronously call a
 * Remote Function", which a release build reports as a crash. A plain function has to be passed
 * to `scheduleOnRN` instead, or the helper needs the "worklet" directive. This test compiles
 * the fork's podcasts files with the real worklets plugin and fails when a worklet calls a
 * function imported from a fork file that is not itself a worklet. Imports from packages are
 * trusted (`scheduleOnRN`, `withTiming` and the like are worklet-safe).
 */

// The Babel packages ship no types here, so they are loaded without them.
const require = createRequire(import.meta.url)
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const babel: any = require("@babel/core")
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const parser: any = require("@babel/parser")

const ROOT = resolve(__dirname, "../..")
const FOLDERS = ["podcasts", "modules/podcasts"]
const PARSE = { sourceType: "module", plugins: ["typescript", "jsx"] }

// Walks any AST (or plain object) and calls `visit` on every node.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function walk(node: any, visit: (node: any) => void) {
  if (!node || typeof node !== "object") return
  if (Array.isArray(node)) return node.forEach((child) => walk(child, visit))
  if (typeof node.type === "string") visit(node)
  for (const key of Object.keys(node)) {
    if (key !== "loc") walk(node[key], visit)
  }
}

// Where an import of a fork file lives on disk, or null for a package.
function resolveLocal(from: string, source: string): string | null {
  const base = source.startsWith("@/")
    ? join(ROOT, source.slice(2))
    : source.startsWith(".")
      ? resolve(dirname(from), source)
      : null
  if (!base) return null
  const options = [
    base,
    ...[".ts", ".tsx", ".js"].map((e) => base + e),
    ...[".ts", ".tsx"].map((e) => join(base, "index" + e)),
  ]
  return options.find((p) => existsSync(p) && statSync(p).isFile()) ?? null
}

// Whether a file exports `name` as a function that starts with the "worklet" directive.
// Anything that is not a plain function (a constant, a re-export) counts as fine.
function exportsWorklet(file: string, name: string): boolean {
  const ast = parser.parse(readFileSync(file, "utf8"), PARSE)
  let found: boolean | null = null
  const check = (fn: {
    body?: { directives?: { value: { value: string } }[] }
  }) => fn.body?.directives?.some((d) => d.value.value === "worklet") ?? false
  walk(ast.program.body, (node) => {
    if (node.type !== "ExportNamedDeclaration" || !node.declaration) return
    const decl = node.declaration
    if (decl.type === "FunctionDeclaration" && decl.id?.name === name) {
      found = check(decl)
    } else if (decl.type === "VariableDeclaration") {
      for (const d of decl.declarations) {
        const isFn =
          d.init?.type === "ArrowFunctionExpression" ||
          d.init?.type === "FunctionExpression"
        if (d.id.name === name && isFn) found = check(d.init)
      }
    }
  })
  return found ?? true
}

/** The imported fork functions that the worklets in this source call without being worklets. */
export function badWorkletCalls(source: string, filename: string): string[] {
  const imports = new Map<string, { file: string; name: string }>()
  walk(parser.parse(source, PARSE).program.body, (node) => {
    if (node.type !== "ImportDeclaration") return
    const file = resolveLocal(filename, node.source.value)
    if (!file) return
    for (const s of node.specifiers) {
      if (s.type === "ImportSpecifier" && s.importKind !== "type") {
        imports.set(s.local.name, {
          file,
          name: s.imported.name ?? s.imported.value,
        })
      }
    }
  })
  const out = babel.transformSync(source, {
    filename,
    cwd: ROOT,
    configFile: join(ROOT, "babel.config.js"),
    caller: { name: "metro", platform: "ios", bundler: "metro" },
    ast: false,
  })
  // The plugin leaves each worklet's code (and so its closure names) in an `code:"..."` string.
  const bad = new Set<string>()
  walk(
    parser.parse(out.code, { sourceType: "script" }).program.body,
    (node) => {
      if (node.type !== "ObjectProperty" || node.key.name !== "code") return
      if (node.value.type !== "StringLiteral") return
      const worklet = parser.parse(node.value.value, { sourceType: "script" })
      const captured = new Set<string>()
      const called = new Set<string>()
      walk(worklet.program.body, (n) => {
        if (n.type === "ArrayPattern") {
          n.elements.forEach(
            (e: { name?: string } | null) => e?.name && captured.add(e.name),
          )
        }
        if (n.type === "CallExpression" && n.callee.type === "Identifier") {
          called.add(n.callee.name)
        }
      })
      for (const name of called) {
        const from = captured.has(name) ? imports.get(name) : undefined
        if (from && !exportsWorklet(from.file, from.name)) bad.add(name)
      }
    },
  )
  return [...bad].sort()
}

function forkFiles(folder: string): string[] {
  const dir = join(ROOT, folder)
  return readdirSync(dir)
    .filter((f) => /\.tsx?$/.test(f) && !f.endsWith(".test.ts"))
    .map((f) => join(dir, f))
}

describe("worklets call only worklets", () => {
  const files = FOLDERS.flatMap(forkFiles).filter((f) =>
    /["']worklet["']|useAnimated|useDerivedValue|Gesture\./.test(
      readFileSync(f, "utf8"),
    ),
  )

  it("finds the files that use worklets", () => {
    expect(files.length).toBeGreaterThan(0)
  })

  for (const file of files) {
    it(`${file.slice(ROOT.length + 1)} has no plain function calls in its worklets`, () => {
      expect(badWorkletCalls(readFileSync(file, "utf8"), file)).toEqual([])
    })
  }

  // Any existing file will do: the plugin only reads it for the source location.
  const here = join(ROOT, "podcasts", "SeekBar.tsx")
  const wrap = (body: string) =>
    `import { Gesture } from "react-native-gesture-handler"
     import { scheduleOnRN } from "react-native-worklets"
     import { positionAt } from "@/modules/podcasts/playerLook"
     export const pan = Gesture.Pan().onEnd((e) => {
       "worklet"
       ${body}
     })`

  it("catches a worklet that calls a plain imported function", () => {
    expect(
      badWorkletCalls(wrap("scheduleOnRN(print, positionAt(e.x, 1))"), here),
    ).toEqual(["positionAt"])
  })

  it("allows scheduleOnRN and a plain function that is only passed along", () => {
    expect(
      badWorkletCalls(wrap("scheduleOnRN(positionAt, e.x)"), here),
    ).toEqual([])
  })
})
