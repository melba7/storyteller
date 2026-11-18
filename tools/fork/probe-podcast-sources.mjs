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

const TIMEOUT_MS = 20_000
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

/** Fetches with a timeout. Never throws: failures come back as `{ error }`. */
async function get(url, headers = {}) {
  try {
    const res = await fetch(url, {
      headers,
      redirect: "follow",
      signal: AbortSignal.timeout(TIMEOUT_MS),
    })
    const bytes = new Uint8Array(await res.arrayBuffer())
    return {
      url,
      status: res.status,
      type: res.headers.get("content-type") ?? "",
      bytes,
    }
  } catch (err) {
    const cause = err?.cause?.code ?? err?.cause?.message ?? ""
    return {
      url,
      error:
        `unreachable: ${err?.name ?? "Error"} ${err?.message ?? ""} ${cause}`.trim(),
    }
  }
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

function fixture(name, data) {
  line(`----- BEGIN FIXTURE ${name} -----`)
  line(JSON.stringify(trimToThree(data), null, 2))
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

async function questionCovers() {
  line("== 1. Apple cover sizes ==")
  const chart = await getJson(`${APPLE_CHART}/50/podcasts.json`)
  const results = chart.json?.feed?.results ?? []
  const cover = results.find(
    (e) => typeof e.artworkUrl100 === "string",
  )?.artworkUrl100
  if (!cover) {
    line(`  overall chart gave no cover address (${describe(chart)})`)
    return false
  }
  line(`  cover address: ${cover}`)
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

async function questionEpisodes() {
  line("== 2. Apple top episodes ==")
  const chart = await getJson(`${APPLE_CHART}/50/podcast-episodes.json`)
  line(`  chart: ${describe(chart)}`)
  const results = chart.json?.feed?.results
  if (!Array.isArray(results) || results.length === 0) return false
  line(`  entries: ${results.length}, fields: ${fieldsOf(results).join(", ")}`)
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
  // The show id is the number after /id in an episode's page address.
  const showIds = results
    .slice(0, 3)
    .map((e) => /\/id(\d+)/.exec(e.url ?? "")?.[1])
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

/** Looks for chart addresses on Spotify's own page, in case the plan's guess is off. */
async function spotifyPageAddresses() {
  const page = await get(`${SPOTIFY}/`, { "User-Agent": BROWSER_UA })
  if (page.error) {
    line(`  charts page: ${page.error}`)
    return
  }
  const html = new TextDecoder().decode(page.bytes)
  const scripts = [...html.matchAll(/<script[^>]+src="([^"]+)"/g)]
    .map((m) => m[1])
    .slice(0, 8)
  const found = new Set(html.match(/\/?api\/[A-Za-z0-9_/.?=&-]+/g) ?? [])
  for (const src of scripts) {
    const url = new URL(src, SPOTIFY).href
    const js = await get(url, { "User-Agent": BROWSER_UA })
    if (js.error) continue
    const text = new TextDecoder().decode(js.bytes)
    for (const m of text.match(/\/?api\/charts[A-Za-z0-9_/.?=&-]*/g) ?? [])
      found.add(m)
  }
  line(`  charts page: ${describe(page)}, ${scripts.length} scripts read`)
  line(
    `  addresses found there: ${[...found].slice(0, 15).join(" ") || "none"}`,
  )
}

async function questionSpotify() {
  line("== 3. Spotify charts ==")
  const names = ["top", "trending", "top_episodes"]
  const outcome = {}
  for (const name of names) {
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
    }
    const list = spotifyList(r.json)
    line(
      `  ${name}: ${list.length} entries, fields: ${fieldsOf(list).join(", ") || "none"}`,
    )
    if (r.json) fixture(`spotify-${name}`, r.json)
    outcome[name] = list.length > 0 ? used : null
  }
  if (!outcome.top) await spotifyPageAddresses()
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
  return { chart: count >= 100, tree: subs > 0 }
}

async function main() {
  const [major] = process.versions.node.split(".").map(Number)
  if (major < 18) {
    console.error(
      `Node 18 or newer is needed (this is ${process.version}); it has no built-in fetch before that.`,
    )
    return
  }
  const covers = await questionCovers()
  const episodes = await questionEpisodes()
  const spotify = await questionSpotify()
  const overall = await questionOverallAndGenres()
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
