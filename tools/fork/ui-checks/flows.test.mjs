// Tests for the simulator checks' files (see README.md in this folder). They read the flows as
// text, because Maestro itself needs a Mac and a simulator. They catch a command that Maestro's
// documentation does not list, a subflow that does not exist, a test id the app does not have, a
// selector written for only one of the two modes, a script that is not executable and a file
// that must never be in the repository.
// Run: node --test 'tools/fork/ui-checks/*.test.mjs'
import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import {
  chmodSync,
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs"
import { tmpdir } from "node:os"
import { dirname, extname, join, relative, resolve } from "node:path"
import { test } from "node:test"
import { fileURLToPath } from "node:url"

const here = dirname(fileURLToPath(import.meta.url))
const flowsDir = join(here, "flows")

/** The commands the flows may use. Each one is on a page of docs.maestro.dev's API reference. */
const COMMANDS = new Set([
  "assertNotVisible",
  "assertVisible",
  "extendedWaitUntil",
  "inputText",
  "launchApp",
  "repeat",
  "runFlow",
  "scroll",
  "swipe",
  "takeScreenshot",
  "tapOn",
])

/** The test ids the app's Podcasts screens get in milestone S1. */
const TEST_IDS = new Set([
  "podcasts-mini-player",
  "podcasts-player",
  "podcasts-player-close",
])

/** The four flows Mo (or CI) runs. The files in `flows/lib` are only called by these. */
const FLOWS = [
  "smoke",
  "player-opens-once",
  "player-tap-during-close",
  "scroll",
]

function yamlFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) =>
    entry.isDirectory()
      ? yamlFiles(join(dir, entry.name))
      : extname(entry.name) === ".yaml"
        ? [join(dir, entry.name)]
        : [],
  )
}

function allFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) =>
    entry.isDirectory()
      ? allFiles(join(dir, entry.name))
      : [join(dir, entry.name)],
  )
}

/** The lines of a flow without comments. */
function codeLines(file) {
  return readFileSync(file, "utf8")
    .split("\n")
    .filter((line) => !line.trim().startsWith("#"))
}

test("the four flows exist at the top of flows/", () => {
  for (const name of FLOWS) {
    assert.ok(existsSync(join(flowsDir, `${name}.yaml`)), `${name}.yaml`)
  }
  // Maestro runs only the files at the top of a folder, so a stray file would be run as a flow.
  const top = readdirSync(flowsDir).filter((n) => n.endsWith(".yaml"))
  assert.deepEqual(top.sort(), FLOWS.map((n) => `${n}.yaml`).sort())
})

test("every flow starts with the app id from the environment", () => {
  for (const file of yamlFiles(flowsDir)) {
    const text = readFileSync(file, "utf8")
    const [header, commands] = text.split(/^---$/m)
    assert.ok(commands, `${relative(here, file)} has no --- line`)
    assert.match(header, /^appId: \$\{APP_ID\}$/m, relative(here, file))
  }
})

test("every command is one the documentation lists", () => {
  for (const file of yamlFiles(flowsDir)) {
    for (const line of codeLines(file)) {
      const match = /^\s*-\s+([A-Za-z]+)\s*(?::|$)/.exec(line)
      if (!match) continue
      assert.ok(
        COMMANDS.has(match[1]),
        `${relative(here, file)}: "${match[1]}" is not in the list of commands`,
      )
    }
  }
})

test("every subflow that is called exists", () => {
  for (const file of yamlFiles(flowsDir)) {
    for (const line of codeLines(file)) {
      const target =
        /^\s*-\s+runFlow:\s+(\S+\.yaml)\s*$/.exec(line)?.[1] ??
        /^\s*file:\s+(\S+\.yaml)\s*$/.exec(line)?.[1]
      if (!target) continue
      const path = resolve(dirname(file), target)
      assert.ok(existsSync(path), `${relative(here, file)} calls ${target}`)
    }
  }
})

test("an id selector is one of the three test ids", () => {
  for (const file of yamlFiles(flowsDir)) {
    for (const line of codeLines(file)) {
      const match = /^\s*id:\s+"?([^"\s]+)"?\s*$/.exec(line)
      if (!match) continue
      assert.ok(
        TEST_IDS.has(match[1]),
        `${relative(here, file)}: unknown id ${match[1]}`,
      )
    }
  }
})

test("a step that uses an id also has the same step for the labels", () => {
  for (const file of yamlFiles(join(flowsDir, "lib"))) {
    const text = readFileSync(file, "utf8")
    const usesIds = /^\s*id:/m.test(text)
    const hasIdsBranch = text.includes("${SELECTORS == 'ids'}")
    const hasLabelsBranch = text.includes("${SELECTORS != 'ids'}")
    assert.equal(hasIdsBranch, usesIds, relative(here, file))
    if (usesIds) assert.ok(hasLabelsBranch, `${relative(here, file)}: labels`)
  }
})

test("the only conditions are the two selector modes", () => {
  for (const file of yamlFiles(flowsDir)) {
    for (const line of codeLines(file)) {
      const match = /^\s*true:\s+(.*)$/.exec(line)
      if (!match) continue
      assert.match(match[1], /^\$\{SELECTORS (==|!=) 'ids'\}$/)
    }
  }
})

test("the scripts are executable and have no syntax error", () => {
  const scripts = readdirSync(here).filter(
    (name) => name.endsWith(".sh") || name.endsWith(".command"),
  )
  assert.ok(scripts.includes("run.sh"))
  assert.ok(scripts.includes("Run the UI checks.command"))
  assert.ok(scripts.includes("Install the UI check tools.command"))
  for (const name of scripts) {
    const path = join(here, name)
    assert.ok(statSync(path).mode & 0o111, `${name} is not executable`)
    const result = spawnSync("bash", ["-n", path], { encoding: "utf8" })
    assert.equal(result.status, 0, `${name}: ${result.stderr}`)
  }
})

test("run.sh knows the same flows as the folder", () => {
  const script = readFileSync(join(here, "run.sh"), "utf8")
  const line = /^ALL_FLOWS="([^"]*)"$/m.exec(script)
  assert.ok(line, "run.sh has no ALL_FLOWS line")
  assert.deepEqual(line[1].split(" "), FLOWS)
})

/**
 * Runs run.sh --build in a made-up checkout where every tool is a stub. The stub for pre-install
 * rewrites package.json the way the real script does, and the `yarn` stub fails when told to.
 */
function runBuild(yarnFails) {
  // The folder `scratchPath()` in libraries/fs would give (this file does not depend on it).
  const scratch =
    // oxlint-disable-next-line storyteller/no-tmpdir
    process.env["STORYTELLER_SCRATCH_DIR"] || tmpdir()
  const root = mkdtempSync(join(scratch, "ui-checks-build-"))
  try {
    const checkout = join(root, "repo")
    const mobile = join(checkout, "applications/mobile")
    // run.sh puts this folder (the one Maestro's installer uses) first on the PATH.
    const bin = join(root, ".maestro/bin")
    const results = join(root, "results")
    mkdirSync(join(checkout, "tools/fork/ui-checks"), { recursive: true })
    mkdirSync(join(checkout, "tools/fork"), { recursive: true })
    mkdirSync(join(mobile, "scripts"), { recursive: true })
    mkdirSync(join(mobile, "ios/App.xcworkspace"), { recursive: true })
    mkdirSync(bin, { recursive: true })
    copyFileSync(
      join(here, "run.sh"),
      join(checkout, "tools/fork/ui-checks/run.sh"),
    )
    const original =
      '{\n  "name": "mobile",\n  "devDependencies": {\n    "@storyteller-platform/web": "workspace:*"\n  }\n}\n'
    writeFileSync(join(mobile, "package.json"), original)
    const stub = (path, body) => {
      writeFileSync(path, `#!/bin/sh\n${body}\n`)
      chmodSync(path, 0o755)
    }
    stub(join(mobile, "scripts/pre-install.mjs"), `printf '{}' > package.json`)
    stub(
      join(bin, "xcrun"),
      `printf '%s\\n' '== Devices ==' '-- iOS 26.0 --' '    iPhone 17 Pro (AAAAAAAA-0000-0000-0000-000000000000) (Shutdown)'`,
    )
    stub(join(bin, "maestro"), "exit 0")
    for (const name of ["corepack", "pod", "ruby", "xcodebuild"]) {
      stub(join(bin, name), "exit 0")
    }
    // The build sees the rewritten package.json, then fails or goes on.
    stub(
      join(bin, "yarn"),
      `cp "${join(mobile, "package.json")}" "${join(root, "seen.json")}"\n${yarnFails ? "exit 1" : "exit 0"}`,
    )
    const run = spawnSync(
      "bash",
      [
        join(checkout, "tools/fork/ui-checks/run.sh"),
        "--build",
        "--results",
        results,
      ],
      {
        encoding: "utf8",
        env: {
          ...process.env,
          HOME: root,
          PATH: `${bin}:${process.env.PATH}`,
        },
      },
    )
    return {
      original,
      run,
      after: readFileSync(join(mobile, "package.json"), "utf8"),
      seen: readFileSync(join(root, "seen.json"), "utf8"),
      kept: existsSync(results) && readdirSync(results),
    }
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
}

for (const [what, yarnFails] of [
  ["a build that works", false],
  ["a build that fails", true],
]) {
  test(`run.sh puts package.json back after ${what}`, () => {
    const { original, run, after, seen, kept } = runBuild(yarnFails)
    // The build did change the file, so the check below means something.
    assert.notEqual(seen, original, run.stdout + run.stderr)
    assert.equal(after, original, run.stdout + run.stderr)
    // Both runs end early (no app to check), so the exit code is "could not run".
    assert.equal(run.status, 2, run.stdout + run.stderr)
    // The copy of the file is kept in the results folder.
    assert.ok(kept && kept.includes("package.json.before-build"), String(kept))
  })
}

test("the folder holds no audio, keys or .env files", () => {
  for (const file of allFiles(here)) {
    const name = file.split("/").pop() ?? ""
    assert.ok(
      !/\.(mp3|m4a|wav|aac|flac|ogg|mp4|mov|p8|pem|key)$/i.test(name) &&
        !name.startsWith(".env"),
      relative(here, file),
    )
  }
})
