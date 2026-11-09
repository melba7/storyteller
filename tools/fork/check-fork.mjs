#!/usr/bin/env node
/**
 * @fileoverview
 *
 * Keeps the Storyteller Lofi fork small and easy to sync. See FORK.md.
 *
 * 1. Every hook in an upstream file still has its LOFI-FORK markers, so an
 *    upstream sync can never drop one silently.
 * 2. Only the touch points listed in touchpoints.json carry markers.
 * 3. The fork commits no audio files: the music is personal and this repository
 *    is public.
 * 4. Measured against the upstream release the fork is based on, the fork
 *    changes no upstream file other than its registered touch points.
 *
 * Usage: node tools/fork/check-fork.mjs [--base <upstream ref>] [--list]
 *
 * Without --base, the base is the newest stable upstream `mobile-vX.Y.Z`
 * release that HEAD contains (see upstream-base.mjs). Plain Node, no
 * dependencies, so it runs before `yarn install`.
 */

import { execFileSync } from "node:child_process"
import { existsSync, readFileSync } from "node:fs"
import { join } from "node:path"

import { findUpstreamBase } from "./upstream-base.mjs"

const AUDIO_EXTENSIONS = new Set([
  "aac",
  "aif",
  "aifc",
  "aiff",
  "alac",
  "caf",
  "flac",
  "m4a",
  "m4b",
  "m4p",
  "mp3",
  "oga",
  "ogg",
  "opus",
  "wav",
  "wave",
  "weba",
  "wma",
])

const STATUS_WORDS = {
  A: "adds",
  D: "deletes",
  M: "modifies",
  T: "changes the type of",
}

const root = execFileSync("git", ["rev-parse", "--show-toplevel"], {
  encoding: "utf8",
}).trim()

const manifestPath = "tools/fork/touchpoints.json"
const manifest = JSON.parse(readFileSync(join(root, manifestPath), "utf8"))
const marker = manifest.marker

const errors = []
const inActions = process.env["GITHUB_ACTIONS"] === "true"

function print(line = "") {
  process.stdout.write(`${line}\n`)
}

function fail(file, message) {
  errors.push(`${file}: ${message}`)
  if (inActions) {
    print(`::error file=${file},title=Fork check::${message}`)
  }
}

function git(...args) {
  return execFileSync("git", args, {
    cwd: root,
    encoding: "utf8",
    maxBuffer: 256 * 1024 * 1024,
  })
}

function gitLines(...args) {
  return git(...args)
    .split("\n")
    .filter((line) => line !== "")
}

function isForkPath(path) {
  return manifest.forkPaths.some((forkPath) =>
    forkPath.endsWith("/") ? path.startsWith(forkPath) : path === forkPath,
  )
}

function isAudio(path) {
  const name = path.slice(path.lastIndexOf("/") + 1)
  const dot = name.lastIndexOf(".")
  return dot > 0 && AUDIO_EXTENSIONS.has(name.slice(dot + 1).toLowerCase())
}

function countOccurrences(text, needle) {
  return text.split(needle).length - 1
}

function parseArgs(argv) {
  const options = { base: process.env["FORK_BASE"] || undefined, list: false }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === "--base" && argv[i + 1]) {
      options.base = argv[++i]
    } else if (arg === "--list") {
      options.list = true
    } else {
      print("Usage: node tools/fork/check-fork.mjs [--base <ref>] [--list]")
      process.exit(arg === "--help" || arg === "-h" ? 0 : 2)
    }
  }
  return options
}

const options = parseArgs(process.argv.slice(2))
const touchpointFiles = new Set(manifest.touchpoints.map(({ file }) => file))
const allowedChanges = new Set(manifest.allowedChanges)
const allowedAudio = new Set(manifest.allowedAudio)

// 1. Every registered hook still carries its markers.
let markerCount = 0
for (const { file, markers } of manifest.touchpoints) {
  markerCount += markers
  if (!existsSync(join(root, file))) {
    fail(
      file,
      `touch point is missing. Upstream may have moved or deleted it; re-apply the hook and update ${manifestPath}.`,
    )
    continue
  }
  const found = countOccurrences(readFileSync(join(root, file), "utf8"), marker)
  if (found !== markers) {
    fail(
      file,
      `expected ${markers} ${marker} marker(s) but found ${found}. If a sync dropped a hook, re-apply it; if the hook changed on purpose, update ${manifestPath}.`,
    )
  }
}

// 2. Only registered touch points carry markers.
let markedFiles = []
try {
  markedFiles = gitLines("grep", "-l", "-I", "-F", "-e", marker, "--", ".")
} catch (error) {
  // git grep exits with 1 when nothing matches.
  if (error.status !== 1) throw error
}
for (const file of markedFiles) {
  if (!touchpointFiles.has(file) && !isForkPath(file)) {
    fail(
      file,
      `has a ${marker} marker but is not a touch point in ${manifestPath}. Register it there and in FORK.md.`,
    )
  }
}

// 3. No audio files in the fork's own folders.
const forkFiles = gitLines("ls-files", "--", ...manifest.forkPaths)
for (const file of forkFiles) {
  if (isAudio(file) && !allowedAudio.has(file)) {
    fail(
      file,
      "is an audio file. Music stays out of git because this repository is public; keep it in a git-ignored folder.",
    )
  }
}

// 4. Measured against upstream, the fork only touches what it registered.
const upstreamBase =
  options.base === undefined ? findUpstreamBase(root) : undefined
const base = options.base ?? upstreamBase?.commit
const baseName = options.base ?? upstreamBase?.name
const footprint = { forkOwned: [], touchpoints: [], allowed: [] }
if (base === undefined) {
  const message =
    "Skipped the upstream footprint check: found no upstream mobile-v* release in HEAD's history. Is gitlab.com reachable? Or pass --base <ref>."
  print(inActions ? `::warning title=Fork check::${message}` : message)
} else {
  const fields = git(
    "diff",
    "--name-status",
    "--no-renames",
    "-z",
    base,
    "HEAD",
  )
    .split("\0")
    .filter((field) => field !== "")
  for (let i = 0; i + 1 < fields.length; i += 2) {
    const status = fields[i]
    const file = fields[i + 1]
    if (status !== "D" && isAudio(file) && !allowedAudio.has(file)) {
      fail(
        file,
        "the fork adds or changes an audio file. Music stays out of git because this repository is public.",
      )
    }
    if (isForkPath(file)) {
      footprint.forkOwned.push(`${status} ${file}`)
    } else if (touchpointFiles.has(file)) {
      footprint.touchpoints.push(`${status} ${file}`)
      if (status === "D") {
        fail(file, "the fork deletes a registered touch point.")
      }
    } else if (allowedChanges.has(file)) {
      footprint.allowed.push(`${status} ${file}`)
    } else {
      const verb = STATUS_WORDS[status] ?? "changes"
      fail(
        file,
        `the fork ${verb} this upstream file, but it is not a registered touch point. Move the change into a fork-owned folder, or register the file in ${manifestPath} and FORK.md.`,
      )
    }
  }
}

print(
  `Fork checks${baseName === undefined ? "" : ` against upstream ${baseName}`}`,
)
print(
  `- ${manifest.touchpoints.length} touch point(s), ${markerCount} ${marker} marker(s) expected`,
)
print(`- ${forkFiles.length} file(s) in fork-owned paths`)
if (base !== undefined) {
  print(
    `- footprint: ${footprint.forkOwned.length} fork-owned, ${footprint.touchpoints.length} touch point(s), ${footprint.allowed.length} other allowed change(s)`,
  )
  if (options.list) {
    for (const [group, entries] of Object.entries(footprint)) {
      print(`  ${group}:`)
      for (const entry of entries) print(`    ${entry}`)
    }
  }
}

if (errors.length > 0) {
  print()
  print(`${errors.length} problem(s):`)
  for (const error of errors) print(`- ${error}`)
  process.exitCode = 1
} else {
  print("All fork checks passed.")
}
