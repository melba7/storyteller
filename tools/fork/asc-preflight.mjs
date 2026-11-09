#!/usr/bin/env node
/**
 * Checks the App Store Connect setup before .github/workflows/testflight.yml
 * starts its hour-long macOS build, so a missed setup step fails in under a
 * minute with the fix spelled out. See FORK.md ("TestFlight").
 *
 * Usage: node tools/fork/asc-preflight.mjs
 *
 * Reads ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 and APPLE_TEAM_ID from the
 * environment and the bundle ID from applications/mobile/fork.config.ts. It:
 * - checks the four values look right (the usual copy and paste slips),
 * - signs in to the App Store Connect API with the key,
 * - registers the App ID if it isn't registered yet,
 * - checks that an App Store Connect app exists for the bundle ID, which only
 *   a person can create.
 *
 * Signing certificates and profiles are left to Xcode's cloud signing during
 * the export, so this never creates or revokes certificates.
 */
import { createPrivateKey, sign } from "node:crypto"
import { appendFileSync } from "node:fs"
import { pathToFileURL } from "node:url"

const API = "https://api.appstoreconnect.apple.com"

export class SetupError extends Error {
  constructor(title, message) {
    super(message)
    this.title = title
  }
}

/** Accepts the .p8 text as pasted, including the slips GitHub secrets invite. */
export function readPrivateKey(p8) {
  let text = (p8 ?? "").trim()
  // Pasted through a tool that turned the line breaks into literal "\n".
  if (!text.includes("\n") && text.includes("\\n")) {
    text = text.replaceAll("\\n", "\n")
  }
  // Only the base64 body, without the BEGIN and END lines.
  if (!text.includes("-----BEGIN")) {
    text = `-----BEGIN PRIVATE KEY-----\n${text.replace(/\s+/g, "")}\n-----END PRIVATE KEY-----`
  }
  try {
    const key = createPrivateKey(text)
    if (key.asymmetricKeyType !== "ec") throw new Error("not an EC key")
    return key
  } catch {
    throw new SetupError(
      "ASC_KEY_P8 is not an App Store Connect key",
      "Paste the whole text of the AuthKey_….p8 file into the ASC_KEY_P8 secret, including the -----BEGIN PRIVATE KEY----- and -----END PRIVATE KEY----- lines.",
    )
  }
}

export function checkValues(env) {
  const problems = []
  const keyId = (env.ASC_KEY_ID ?? "").trim()
  const issuerId = (env.ASC_ISSUER_ID ?? "").trim()
  const teamId = (env.APPLE_TEAM_ID ?? "").trim()
  if (!/^[A-Z0-9]{10}$/.test(keyId)) {
    problems.push(
      `ASC_KEY_ID should be the key's 10-character Key ID (like 2X9R4HXF34), from the key list in App Store Connect → Users and Access → Integrations. It is "${keyId}".`,
    )
  }
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      issuerId,
    )
  ) {
    problems.push(
      "ASC_ISSUER_ID should be the Issuer ID shown above the key list in App Store Connect → Users and Access → Integrations (a UUID like 57246542-96fe-1a63-e053-0824d011072a).",
    )
  }
  if (!/^[A-Z0-9]{10}$/.test(teamId)) {
    problems.push(
      `APPLE_TEAM_ID should be the 10-character Team ID from developer.apple.com → Account → Membership details. It is "${teamId}".`,
    )
  }
  if (problems.length > 0) {
    throw new SetupError(
      "Some TestFlight secrets look wrong",
      problems.join(" "),
    )
  }
  return { keyId, issuerId, teamId }
}

/** An App Store Connect API token (ES256 JWT), valid for 10 minutes. */
export function makeToken({ keyId, issuerId, key, now = Date.now() }) {
  const encode = (value) =>
    Buffer.from(JSON.stringify(value)).toString("base64url")
  const issuedAt = Math.floor(now / 1000)
  const input = `${encode({ alg: "ES256", kid: keyId, typ: "JWT" })}.${encode({
    iss: issuerId,
    iat: issuedAt,
    exp: issuedAt + 10 * 60,
    aud: "appstoreconnect-v1",
  })}`
  const signature = sign("sha256", Buffer.from(input), {
    key,
    dsaEncoding: "ieee-p1363",
  })
  return `${input}.${signature.toString("base64url")}`
}

function describeFailure(status, body) {
  const details = (body?.errors ?? [])
    .map((error) => error.detail || error.title || error.code)
    .filter(Boolean)
    .join(" ")
  const codes = (body?.errors ?? []).map((error) => error.code ?? "").join(" ")
  if (status === 401) {
    return new SetupError(
      "App Store Connect refused the API key",
      "Check that ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 all come from the same key in App Store Connect → Users and Access → Integrations, and that the key hasn't been revoked.",
    )
  }
  if (status === 403 && /AGREEMENT/i.test(codes)) {
    return new SetupError(
      "An Apple agreement needs accepting",
      `Sign in to developer.apple.com and App Store Connect and accept any pending agreements. Apple said: ${details}`,
    )
  }
  if (status === 403) {
    return new SetupError(
      "The API key isn't allowed to do this",
      `Create a team key with Admin access (App Store Connect → Users and Access → Integrations) and put it in the secrets. Apple said: ${details}`,
    )
  }
  return new SetupError(
    `App Store Connect answered ${status}`,
    details || "No details given. Run the workflow again later.",
  )
}

export async function preflight({ env, appId, appName, fetchImpl = fetch }) {
  const { keyId, issuerId, teamId } = checkValues(env)
  const key = readPrivateKey(env.ASC_KEY_P8)
  const token = makeToken({ keyId, issuerId, key })
  const notes = []

  const call = async (method, path, body) => {
    let response
    try {
      response = await fetchImpl(`${API}${path}`, {
        method,
        headers: {
          authorization: `Bearer ${token}`,
          ...(body ? { "content-type": "application/json" } : {}),
        },
        body: body ? JSON.stringify(body) : undefined,
        signal: AbortSignal.timeout(60_000),
      })
    } catch (error) {
      throw new SetupError(
        "Couldn't reach App Store Connect",
        `${(error.cause?.message ?? error.message).replace(/\.+$/, "")}. Run the workflow again later.`,
      )
    }
    const text = await response.text()
    let json
    try {
      json = text ? JSON.parse(text) : {}
    } catch {
      json = {}
    }
    if (!response.ok) throw describeFailure(response.status, json)
    return json
  }

  // filter[identifier] also matches longer IDs, such as the .dev variant.
  const query = new URLSearchParams({
    "filter[identifier]": appId,
    limit: "200",
  })
  const bundleIds = await call("GET", `/v1/bundleIds?${query}`)
  let bundleId = bundleIds.data?.find(
    (entry) => entry.attributes?.identifier === appId,
  )
  if (bundleId) {
    notes.push(`App ID ${appId} is registered.`)
  } else {
    const created = await call("POST", "/v1/bundleIds", {
      data: {
        type: "bundleIds",
        attributes: {
          identifier: appId,
          // App ID names allow only letters, digits and spaces.
          name: appName.replace(/[^A-Za-z0-9 ]+/g, " ").trim(),
          platform: "IOS",
        },
      },
    })
    bundleId = created.data
    notes.push(`Registered the App ID ${appId}.`)
  }
  const seedId = bundleId?.attributes?.seedId
  if (seedId && seedId !== teamId) {
    notes.push(
      `Note: the App ID's prefix is ${seedId} but APPLE_TEAM_ID is ${teamId}. If the export fails with a team error, check APPLE_TEAM_ID against Membership details on developer.apple.com.`,
    )
  }

  const apps = await call(
    "GET",
    `/v1/apps?${new URLSearchParams({ "filter[bundleId]": appId })}`,
  )
  const app = apps.data?.find((entry) => entry.attributes?.bundleId === appId)
  if (!app) {
    throw new SetupError(
      "Create the app in App Store Connect",
      `There is no App Store Connect app for ${appId} yet, and Apple only lets a person create one. In App Store Connect → Apps, click +, choose New App, tick iOS, pick the bundle ID ${appId}, and give it any unused name (it's never published) and any SKU. Then run this workflow again.${notes.length ? ` (${notes.join(" ")})` : ""}`,
    )
  }
  notes.push(
    `App Store Connect app "${app.attributes?.name}" exists for ${appId}.`,
  )
  return notes
}

async function main() {
  const { forkIdentity } = await import(
    new URL("../../applications/mobile/fork.config.ts", import.meta.url).href
  )
  const summary = process.env["GITHUB_STEP_SUMMARY"]
  const inActions = process.env["GITHUB_ACTIONS"] === "true"
  try {
    const notes = await preflight({
      env: process.env,
      appId: forkIdentity.appId,
      appName: forkIdentity.name,
    })
    for (const note of notes) console.log(note)
    if (summary) {
      appendFileSync(
        summary,
        `App Store Connect setup checked:\n\n${notes.map((note) => `- ${note}`).join("\n")}\n`,
      )
    }
  } catch (error) {
    if (!(error instanceof SetupError)) throw error
    // Workflow commands end at a line break, so keep the message on one line.
    const message = error.message.replace(/\s*\n\s*/g, " ")
    if (inActions) {
      console.log(`::error title=${error.title}::${message}`)
    } else {
      console.error(`${error.title}: ${message}`)
    }
    if (summary) appendFileSync(summary, `**${error.title}.** ${message}\n`)
    process.exitCode = 1
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main()
}
