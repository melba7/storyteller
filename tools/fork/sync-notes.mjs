#!/usr/bin/env node
/**
 * @fileoverview
 *
 * Writes the body of an upstream sync pull request, or of the issue opened
 * when a sync needs a manual merge, to stdout. Used by
 * .github/workflows/upstream-sync.yml. See FORK.md ("Upstream updates").
 *
 * Usage: node tools/fork/sync-notes.mjs --kind pull-request|conflict|blocked
 *          --tag <tag> --branch <branch> --repo <owner/name>
 *          [--base-tag <tag>] [--status <status>] [--conflicts <files>]
 *          [--error <text>] [--owner <login>]
 *
 * Upstream's release notes come from GitLab and are rewritten so that they
 * cannot reach anyone on GitHub: GitLab references become plain links and
 * @-handles are put in code spans, so nobody upstream gets pinged or
 * backlinked from this fork.
 */

const UPSTREAM = "https://gitlab.com/storyteller-platform/storyteller"
const UPSTREAM_PROJECT = "storyteller-platform/storyteller"
const UPSTREAM_API = `https://gitlab.com/api/v4/projects/${encodeURIComponent(UPSTREAM_PROJECT)}`

function parseArgs(argv) {
  const options = {}
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i]
    const value = argv[i + 1]
    if (!key?.startsWith("--") || value === undefined) {
      throw new Error(`Unexpected argument: ${key}`)
    }
    options[key.slice(2)] = value
  }
  for (const required of ["kind", "tag", "branch", "repo"]) {
    if (!options[required]) throw new Error(`Missing --${required}`)
  }
  return options
}

/** Make GitLab markdown safe and useful on GitHub. */
function sanitizeReleaseNotes(markdown) {
  const project = UPSTREAM_PROJECT
  return (
    markdown
      // storyteller-platform/storyteller@<sha>, !<mr> and #<issue>
      .replace(
        new RegExp(`${project}@([0-9a-f]{7,40})`, "g"),
        `${UPSTREAM}/-/commit/$1`,
      )
      .replace(
        new RegExp(`${project}!(\\d+)`, "g"),
        `${UPSTREAM}/-/merge_requests/$1`,
      )
      .replace(new RegExp(`${project}#(\\d+)`, "g"), `${UPSTREAM}/-/issues/$1`)
      // Bare !123 and #123 refer to upstream merge requests and issues.
      .replace(
        /(^|[\s(])!(\d+)\b/gm,
        `$1[!$2](${UPSTREAM}/-/merge_requests/$2)`,
      )
      .replace(/(^|[\s(])#(\d+)\b/gm, `$1[#$2](${UPSTREAM}/-/issues/$2)`)
      // @handle would ping whoever owns that name on GitHub.
      .replace(/(^|[^\w`/.@-])@([A-Za-z0-9][\w.-]*)/g, "$1`@$2`")
  )
}

async function fetchReleaseNotes(tag) {
  try {
    const response = await fetch(
      `${UPSTREAM_API}/releases/${encodeURIComponent(tag)}`,
      { signal: AbortSignal.timeout(15_000) },
    )
    if (!response.ok) return undefined
    const release = await response.json()
    return typeof release.description === "string"
      ? release.description.trim()
      : undefined
  } catch {
    return undefined
  }
}

function quote(markdown) {
  return markdown
    .split("\n")
    .map((line) => (line === "" ? ">" : `> ${line}`))
    .join("\n")
}

function upstreamLinks({ tag, "base-tag": baseTag }) {
  const isTag = tag.startsWith("mobile-v")
  const lines = []
  if (isTag) {
    lines.push(`- Upstream release: ${UPSTREAM}/-/releases/${tag}`)
  }
  if (baseTag) {
    lines.push(
      `- Upstream changes since \`${baseTag}\`, the release \`main\` has now: ${UPSTREAM}/-/compare/${baseTag}...${tag}`,
    )
  }
  return lines
}

async function pullRequestBody(options) {
  const lines = [
    `This merges upstream Storyteller \`${options.tag}\` into \`main\`. It was opened by the daily upstream sync (\`.github/workflows/upstream-sync.yml\`).`,
    "",
    ...upstreamLinks(options),
    options.status === "merged-lockfile"
      ? "- Merge: only `yarn.lock` conflicted. The branch takes upstream's lockfile and reran `yarn install` to add the fork's dependencies back."
      : "- Merge: clean, no conflicts.",
    "",
    "Before merging:",
    "",
    "- [ ] Fork CI passed: touch-point check, mobile typecheck and tests, iOS simulator build.",
    "- [ ] Upstream's changes to the touch-point files listed in `FORK.md` still fit the fork's hooks.",
    "- [ ] Merge with **Create a merge commit**. Never squash or rebase a sync pull request.",
    "",
    "If an older sync pull request is still open, this one includes it; close the older one.",
  ]
  if (options.tag.startsWith("mobile-v")) {
    const notes = await fetchReleaseNotes(options.tag)
    lines.push(
      "",
      "## Upstream release notes",
      "",
      notes
        ? quote(sanitizeReleaseNotes(notes))
        : `Not available from GitLab right now; see ${UPSTREAM}/-/releases/${options.tag}.`,
    )
  }
  if (options.owner) lines.push("", `cc @${options.owner}`)
  return lines.join("\n")
}

function conflictBody(options) {
  const files = (options.conflicts ?? "")
    .split("\n")
    .filter((file) => file !== "")
    .map((file) => `- \`${file}\``)
  return [
    `Upstream Storyteller \`${options.tag}\` does not merge cleanly into \`main\`. These files conflict:`,
    "",
    ...files,
    "",
    ...upstreamLinks(options),
    "",
    "To finish the merge by hand, in a clone of this fork:",
    "",
    "```sh",
    "tools/fork/setup-clone.sh   # once per clone",
    "git fetch origin",
    `tools/fork/sync-upstream.sh --tag ${options.tag}`,
    "# resolve the conflicts, then:",
    "git add -A && git commit --no-edit",
    "node tools/fork/check-fork.mjs",
    `git push -u origin ${options.branch}`,
    `gh pr create --repo ${options.repo} --base main --head ${options.branch} --title "Sync upstream ${options.tag}"`,
    "```",
    "",
    "Keep every `LOFI-FORK` hook while resolving, and merge the pull request with **Create a merge commit**. Once that branch exists, the daily sync stops reporting this release.",
    ...(options.owner ? ["", `cc @${options.owner}`] : []),
  ].join("\n")
}

function blockedBody(options) {
  return [
    `The daily upstream sync merged \`${options.tag}\` into \`${options.branch}\` but could not publish it:`,
    "",
    "```text",
    (options.error ?? "unknown error").trim(),
    "```",
    "",
    'Usually this means one of these one-time settings is missing (see `FORK.md`, "One-time GitHub settings"):',
    "",
    '- Settings → Actions → General → Workflow permissions: tick "Allow GitHub Actions to create and approve pull requests".',
    "- If pushing failed, add a `SYNC_TOKEN` repository secret: a fine-grained token for this repository with read and write access to contents, pull requests, issues and workflows.",
    "",
    `Then rerun the "Upstream sync" workflow from the Actions tab, or open the pull request yourself if the branch was pushed: https://github.com/${options.repo}/compare/main...${options.branch}?expand=1`,
    ...(options.owner ? ["", `cc @${options.owner}`] : []),
  ].join("\n")
}

const options = parseArgs(process.argv.slice(2))
const bodies = {
  "pull-request": pullRequestBody,
  conflict: conflictBody,
  blocked: blockedBody,
}
const makeBody = bodies[options.kind]
if (!makeBody) throw new Error(`Unknown --kind ${options.kind}`)
process.stdout.write(`${await makeBody(options)}\n`)
