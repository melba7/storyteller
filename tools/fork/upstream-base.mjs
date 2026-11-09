#!/usr/bin/env node
/**
 * @fileoverview
 *
 * Finds the upstream Storyteller release a fork commit is based on: the newest
 * stable `mobile-vX.Y.Z` tag whose commit it contains. Tags come from this
 * clone and from upstream itself, so the fork never has to carry upstream's
 * tags. Used by check-fork.mjs and sync-upstream.sh. See FORK.md.
 *
 * Usage: node tools/fork/upstream-base.mjs [<rev>]
 *
 * Prints the tag name (for HEAD by default), or nothing if there is none.
 */

import { execFileSync } from "node:child_process"
import { pathToFileURL } from "node:url"

export const UPSTREAM_URL =
  "https://gitlab.com/storyteller-platform/storyteller.git"

const STABLE_MOBILE_TAG = /^mobile-v(\d+)\.(\d+)\.(\d+)$/

function git(cwd, args, options = {}) {
  return execFileSync("git", args, {
    cwd,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
    stdio: ["ignore", "pipe", "pipe"],
    ...options,
  })
}

function lines(text) {
  return text.split("\n").filter((line) => line !== "")
}

/** Stable tag name → commit, from this clone. */
function localTags(cwd) {
  const tags = new Map()
  const output = git(cwd, [
    "for-each-ref",
    "--format=%(refname:strip=2) %(objectname) %(*objectname)",
    "refs/tags/mobile-v*",
  ])
  for (const line of lines(output)) {
    const [name, object, peeled] = line.split(" ")
    if (STABLE_MOBILE_TAG.test(name)) tags.set(name, peeled || object)
  }
  return tags
}

/** Stable tag name → commit, from upstream. Empty if upstream is unreachable. */
function upstreamTags(cwd) {
  let url = UPSTREAM_URL
  try {
    url = git(cwd, ["remote", "get-url", "upstream"]).trim()
  } catch {
    // No upstream remote in this clone; use the canonical URL.
  }
  let output
  try {
    output = git(cwd, ["ls-remote", "--tags", url, "refs/tags/mobile-v*"], {
      timeout: 60_000,
    })
  } catch {
    process.stderr.write(`Could not list upstream tags from ${url}.\n`)
    return new Map()
  }
  const tags = new Map()
  for (const line of lines(output)) {
    const [commit, ref] = line.split("\t")
    // Annotated tags are listed twice; the ^{} line holds the commit.
    const name = ref.replace(/^refs\/tags\//, "").replace(/\^\{\}$/, "")
    if (!STABLE_MOBILE_TAG.test(name)) continue
    if (ref.endsWith("^{}") || !tags.has(name)) tags.set(name, commit)
  }
  return tags
}

function version(name) {
  return STABLE_MOBILE_TAG.exec(name).slice(1).map(Number)
}

function newestFirst(a, b) {
  const [va, vb] = [version(a), version(b)]
  for (let i = 0; i < 3; i++) {
    if (va[i] !== vb[i]) return vb[i] - va[i]
  }
  return 0
}

function contains(cwd, rev, commit) {
  try {
    // Never download a missing commit in a partial clone: missing means no.
    git(cwd, ["merge-base", "--is-ancestor", commit, rev], {
      env: { ...process.env, GIT_NO_LAZY_FETCH: "1" },
    })
    return true
  } catch {
    return false
  }
}

/**
 * The newest stable upstream mobile release that `rev` contains, as
 * `{ name, commit }`, or undefined.
 */
export function findUpstreamBase(cwd, rev = "HEAD") {
  const tags = localTags(cwd)
  for (const [name, commit] of upstreamTags(cwd)) tags.set(name, commit)
  for (const name of [...tags.keys()].sort(newestFirst)) {
    const commit = tags.get(name)
    if (contains(cwd, rev, commit)) return { name, commit }
  }
  return undefined
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const root = git(process.cwd(), ["rev-parse", "--show-toplevel"]).trim()
  const base = findUpstreamBase(root, process.argv[2] ?? "HEAD")
  if (base) process.stdout.write(`${base.name}\n`)
}
