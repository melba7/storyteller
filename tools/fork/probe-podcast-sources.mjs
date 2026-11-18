#!/usr/bin/env node
/**
 * Probes the chart addresses the podcast lists plan depends on, from a machine
 * with open internet (a GitHub runner). See docs/PODCASTS-LISTS-PLAN.md, C0.
 *
 * Usage: node tools/fork/probe-podcast-sources.mjs
 *
 * It answers four questions and prints each answer cut down to its first three
 * entries between `----- BEGIN FIXTURE <name> -----` and
 * `----- END FIXTURE <name> -----` lines, so the answers can be copied out of
 * the job log as test fixtures. It ends with one YES or NO line per question.
 * One failing address never stops the rest, and the exit code is always 0
 * because this is a probe, not a check.
 */
import { pathToFileURL } from "node:url"

const TIMEOUT_MS = 30_000
const TRIES = 3
const PAUSE_MS = 1500
const BROWSER_UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
  "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
const APPLE_CHART =
  "https://rss.marketingtools.apple.com/api/v2/us/podcasts/top"
const SPOTIFY = "https://podcastcharts.byspotify.com"

// ---- Image header readers (pure, tested) ----

/** Width and height from the IHDR chunk of a PNG, or null if it isn't one. */
export function pngSize(bytes) {
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
  if (bytes.length < 24 || signature.some((b, i) => bytes[i] !== b)) return null
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  return { width: view.getUint32(16), height: view.getUint32(20) }
}

/** Width and height from the first frame header of a JPEG, or null. */
export function jpegSize(bytes) {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return null
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  let i = 2
  while (i + 4 <= bytes.length) {
    if (bytes[i] !== 0xff) return null
    const marker = bytes[i + 1]
    if (marker === 0xff) {
      i += 1 // fill byte
      continue
    }
    if (
      marker === 0xd8 ||
      (marker >= 0xd0 && marker <= 0xd7) ||
      marker === 0x01
    ) {
      i += 2 // markers with no length
      continue
    }
    const isFrame =
      marker >= 0xc0 &&
      marker <= 0xcf &&
      marker !== 0xc4 &&
      marker !== 0xc8 &&
      marker !== 0xcc
    if (isFrame) {
      if (i + 9 > bytes.length) return null
      return { width: view.getUint16(i + 7), height: view.getUint16(i + 5) }
    }
    i += 2 + view.getUint16(i + 2)
  }
  return null
}

/** Size of a PNG or JPEG, picking the reader from the first bytes. */
export function imageSize(bytes) {
  return pngSize(bytes) ?? jpegSize(bytes)
}

/** The same data with every array cut to its first three entries. */
export function trimToThree(value) {
  if (Array.isArray(value)) return value.slice(0, 3).map(trimToThree)
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([k, v]) => [k, trimToThree(v)]),
    )
  }
  return value
}

// ---- Network helpers ----

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

/**
 * Fetches with a timeout, trying up to three times with a short pause when the
 * request fails or the server answers 429 or 5xx. Never throws: a failure comes
 * back as `{ error }`, and a last bad answer comes back as the answer.
 */
async function get(url, headers = {}) {
  let last
  for (let attempt = 1; attempt <= TRIES; attempt++) {
    if (attempt > 1) await sleep(PAUSE_MS)
    try {
      const res = await fetch(url, {
        headers,
        redirect: "follow",
        signal: AbortSignal.timeout(TIMEOUT_MS),
      })
      const bytes = new Uint8Array(await res.arrayBuffer())
      last = {
        url,
        status: res.status,
        type: res.headers.get("content-type") ?? "",
        bytes,
        attempt,
      }
      if (res.status !== 429 && res.status < 500) return last
    } catch (err) {
      const cause = err?.cause?.code ?? err?.cause?.message ?? ""
      const message =
        `${err?.name ?? "Error"} ${err?.message ?? ""} ${cause}`.trim()
      last = { url, error: `unreachable: ${message} (after ${attempt} tries)` }
    }
  }
  return last
}

/** Fetches JSON. Adds `json` when the body parses and `text` when it doesn't. */
async function getJson(url, headers = {}) {
  const r = await get(url, headers)
  if (r.error) return r
  const text = new TextDecoder().decode(r.bytes)
  try {
    return { ...r, json: JSON.parse(text) }
  } catch {
    return { ...r, text: text.slice(0, 200) }
  }
}

function line(text = "") {
  process.stdout.write(`${text}\n`)
}

function describe(r) {
  if (r.error) return r.error
  return `status ${r.status}, ${r.type || "no content type"}, ${r.bytes.length} bytes`
}

/** The same data with every `showDescription` cut to 80 characters. */
function cutDescriptions(value) {
  if (Array.isArray(value)) return value.map(cutDescriptions)
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([k, v]) => [
        k,
        k === "showDescription" && typeof v === "string"
          ? v.slice(0, 80)
          : cutDescriptions(v),
      ]),
    )
  }
  return value
}

function fixture(name, data) {
  line(`----- BEGIN FIXTURE ${name} -----`)
  line(JSON.stringify(cutDescriptions(trimToThree(data)), null, 2))
  line(`----- END FIXTURE ${name} -----`)
}

/** Keys of the first object in a list, for "which fields?". */
function fieldsOf(list) {
  const first = Array.isArray(list) ? list[0] : null
  return first && typeof first === "object" ? Object.keys(first) : []
}

/** The list inside a Spotify answer: the body itself or its first array property. */
function spotifyList(json) {
  if (Array.isArray(json)) return json
  if (json && typeof json === "object") {
    return Object.values(json).find(Array.isArray) ?? []
  }
  return []
}

// ---- The four questions ----

async function questionCovers(fallbackCover) {
  line("== 1. Apple cover sizes ==")
  const chart = await getJson(`${APPLE_CHART}/50/podcasts.json`)
  const results = chart.json?.feed?.results ?? []
  const cover =
    results.find((e) => typeof e.artworkUrl100 === "string")?.artworkUrl100 ??
    fallbackCover
  if (!cover) {
    line(`  overall chart gave no cover address (${describe(chart)})`)
    return false
  }
  line(
    `  cover address: ${cover}${results.length ? "" : " (from the top-100 chart)"}`,
  )
  const base = cover.replace(/\/[^/]*$/, "")
  const forms = ["100x100bb.png", "640x640bb.jpg", "1280x1280bb.jpg"]
  const rows = []
  for (const form of forms) {
    const r = await get(`${base}/${form}`)
    const size = r.error ? null : imageSize(r.bytes)
    const row = r.error
      ? { form, error: r.error }
      : {
          form,
          status: r.status,
          type: r.type,
          byteSize: r.bytes.length,
          pixels: size,
        }
    rows.push(row)
    line(`  ${form}: ${JSON.stringify(row)}`)
  }
  fixture("apple-cover-sizes", rows)
  const big = rows.find((r) => r.form === "640x640bb.jpg")
  const huge = rows.find((r) => r.form === "1280x1280bb.jpg")
  return big?.status === 200 && big.pixels?.width >= 600 && huge?.status === 200
}

async function questionEpisodes(overallResults) {
  line("== 2. Apple top episodes ==")
  let chart
  for (const name of ["podcast-episodes", "podcast-episode"]) {
    const r = await getJson(`${APPLE_CHART}/50/${name}.json`)
    line(`  ${name}.json: ${describe(r)}`)
    if (
      !chart &&
      Array.isArray(r.json?.feed?.results) &&
      r.json.feed.results.length > 0
    ) {
      chart = { name, ...r }
    }
  }
  if (!chart) return false
  const results = chart.json.feed.results
  line(`  answering address: ${chart.name}.json, ${results.length} entries`)
  line(`  fields: ${fieldsOf(results).join(", ")}`)
  fixture("apple-top-episodes", chart.json)
  const ids = results
    .slice(0, 3)
    .map((e) => e.id)
    .filter(Boolean)
  const tries = [
    [
      "episode-lookup",
      `https://itunes.apple.com/lookup?id=${ids.join(",")}&entity=podcastEpisode`,
    ],
    [
      "episode-lookup-plain",
      `https://itunes.apple.com/lookup?id=${ids.join(",")}`,
    ],
  ]
  // The show id is the number after /id in an episode's page address; when the
  // entries carry none, use the first shows of the overall chart instead.
  let showIds = results
    .slice(0, 3)
    .map((e) => /\/id(\d+)/.exec(e.url ?? "")?.[1])
    .filter(Boolean)
  if (!showIds.length)
    showIds = overallResults
      .slice(0, 3)
      .map((e) => e.id)
      .filter(Boolean)
  if (showIds.length) {
    tries.push([
      "show-lookup",
      `https://itunes.apple.com/lookup?id=${showIds.join(",")}`,
    ])
  }
  let answered = false
  for (const [name, url] of tries) {
    const r = await getJson(url)
    const found = r.json?.results ?? []
    const has = (key) => found.some((x) => x?.[key])
    line(`  ${name}: ${describe(r)}, ${found.length} results`)
    line(
      `    feedUrl: ${has("feedUrl")}, episodeGuid: ${has("episodeGuid")}, episodeUrl: ${has("episodeUrl")}`,
    )
    if (r.json) fixture(name, r.json)
    if (
      name !== "show-lookup" &&
      has("feedUrl") &&
      has("episodeGuid") &&
      has("episodeUrl")
    ) {
      answered = true
    }
  }
  return answered
}

/** Prints about 300 characters around each match of `needle` (at most `max`). */
function printContexts(source, text, needle, max = 6) {
  let from = 0
  for (let n = 0; n < max; n++) {
    const at = text.indexOf(needle, from)
    if (at < 0) return
    const around = text
      .slice(Math.max(0, at - 150), at + 150)
      .replace(/\s+/g, " ")
    line(`  [${source}] around "${needle}": ${around}`)
    from = at + needle.length
  }
}

/**
 * Reads Spotify's charts page and its scripts and prints how the chart address
 * and its query are built. Returns the extra query names and category names found.
 */
async function spotifyPageClues() {
  const clues = { params: new Set(), categories: [] }
  const page = await get(`${SPOTIFY}/`, { "User-Agent": BROWSER_UA })
  if (page.error) {
    line(`  charts page: ${page.error}`)
    return clues
  }
  const html = new TextDecoder().decode(page.bytes)
  const srcs = [...html.matchAll(/<script[^>]+src="([^"]+)"/g)]
    .map((m) => m[1])
    .slice(0, 25)
  line(
    `  charts page: ${describe(page)}, ${srcs.length} scripts: ${srcs.join(" ")}`,
  )
  const sources = [["page", html]]
  for (const src of srcs) {
    const js = await get(new URL(src, SPOTIFY).href, {
      "User-Agent": BROWSER_UA,
    })
    if (!js.error) sources.push([src, new TextDecoder().decode(js.bytes)])
  }
  for (const [source, text] of sources) {
    printContexts(source, text, "api/charts")
    printContexts(source, text, "region=")
    for (const m of text.matchAll(/[?&]([a-zA-Z_]+)=/g)) {
      if (m[1] !== "region") clues.params.add(m[1])
    }
    for (const m of text.matchAll(
      /categor(?:y|ies)["']?\s*[:=]\s*\[?\s*["']([A-Za-z0-9_-]+)["']/gi,
    )) {
      clues.categories.push(m[1])
    }
  }
  line(
    `  other query names seen: ${[...clues.params].slice(0, 20).join(", ") || "none"}`,
  )
  line(
    `  category names seen: ${clues.categories.slice(0, 10).join(", ") || "none"}`,
  )
  return clues
}

async function trySpotify(name, query) {
  const url = `${SPOTIFY}/api/charts/${name}?${query}`
  const r = await getJson(url, {
    "User-Agent": BROWSER_UA,
    Accept: "application/json",
  })
  const list = spotifyList(r.json)
  const body =
    r.error || r.status === 200
      ? ""
      : `, body: ${JSON.stringify(new TextDecoder().decode(r.bytes))}`
  line(`  ${name}?${query}: ${describe(r)}, ${list.length} entries${body}`)
  return { r, list }
}

async function questionSpotify() {
  line("== 3. Spotify charts ==")
  const outcome = {}
  const failed = []
  for (const name of ["top", "trending", "top_episodes"]) {
    const url = `${SPOTIFY}/api/charts/${name}?region=us`
    const plain = await getJson(url)
    let used = "plain"
    let r = plain
    line(`  ${name} plain: ${describe(plain)}`)
    if (plain.error || plain.status !== 200 || !plain.json) {
      r = await getJson(url, {
        "User-Agent": BROWSER_UA,
        Accept: "application/json",
      })
      used = "browser User-Agent"
      line(`  ${name} browser-like: ${describe(r)}`)
      if (!r.error && r.status !== 200) {
        line(
          `  ${name} body: ${JSON.stringify(new TextDecoder().decode(r.bytes))}`,
        )
      }
    }
    const list = spotifyList(r.json)
    line(
      `  ${name}: ${list.length} entries, fields: ${fieldsOf(list).join(", ") || "none"}`,
    )
    if (r.json) fixture(`spotify-${name}`, r.json)
    outcome[name] = list.length > 0 ? used : null
    if (!outcome[name]) failed.push(name)
  }
  if (failed.length) {
    const clues = await spotifyPageClues()
    const queries = []
    for (const p of [...clues.params].slice(0, 5)) {
      for (const v of ["all", "top"]) queries.push(`region=us&${p}=${v}`)
    }
    const cats = ["all", "top", ...clues.categories.slice(0, 1)]
    for (const c of cats) queries.push(`region=us&category=${c}`)
    for (const name of failed) {
      for (const query of queries) {
        const { r, list } = await trySpotify(name, query)
        if (list.length) {
          outcome[name] = `?${query}`
          fixture(`spotify-${name}`, r.json)
          break
        }
      }
    }
  }
  line(`  how each answered: ${JSON.stringify(outcome)}`)
  return outcome
}

async function questionOverallAndGenres() {
  line("== 4. Overall chart with 100 entries, and the genre tree ==")
  const chart = await getJson(`${APPLE_CHART}/100/podcasts.json`)
  const count = chart.json?.feed?.results?.length ?? 0
  line(`  overall 100: ${describe(chart)}, ${count} entries`)
  if (chart.json) fixture("apple-overall-100", chart.json)
  const tree = await getJson(
    "https://itunes.apple.com/WebObjects/MZStoreServices.woa/ws/genres?id=26",
  )
  const root = tree.json?.["26"]
  const subs = root?.subgenres ? Object.keys(root.subgenres).length : 0
  line(`  genre tree: ${describe(tree)}, ${subs} sub-genres under 26`)
  if (tree.json) fixture("apple-genre-tree", tree.json)
  const results = chart.json?.feed?.results ?? []
  const cover = results.find(
    (e) => typeof e.artworkUrl100 === "string",
  )?.artworkUrl100
  return { chart: count >= 100, tree: subs > 0, results, cover }
}

async function main() {
  const [major] = process.versions.node.split(".").map(Number)
  if (major < 18) {
    console.error(
      `Node 18 or newer is needed (this is ${process.version}); it has no built-in fetch before that.`,
    )
    return
  }
  const overall = await questionOverallAndGenres()
  const covers = await questionCovers(overall.cover)
  const episodes = await questionEpisodes(overall.results)
  const spotify = await questionSpotify()
  const yes = (b) => (b ? "YES" : "NO")
  line()
  line("== Summary ==")
  line(
    `1. Apple rewritten cover sizes (640 and 1280 answer with real pixels): ${yes(covers)}`,
  )
  line(
    `2. Top episodes chart answers and a lookup gives feedUrl, episodeGuid, episodeUrl: ${yes(episodes)}`,
  )
  line(
    `3. Spotify top, trending, top_episodes answer: top ${yes(spotify.top)}${spotify.top ? ` (${spotify.top})` : ""}, trending ${yes(spotify.trending)}, top_episodes ${yes(spotify.top_episodes)}`,
  )
  line(
    `4. Overall chart with 100 entries: ${yes(overall.chart)}; genre tree: ${yes(overall.tree)}`,
  )
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  try {
    await main()
  } catch (err) {
    console.error(
      `probe stopped on an unexpected error: ${err?.message ?? err}`,
    )
  }
  process.exitCode = 0
}
