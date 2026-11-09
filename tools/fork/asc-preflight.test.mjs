// Tests for asc-preflight.mjs. Run: node --test tools/fork/
import assert from "node:assert/strict"
import { generateKeyPairSync, verify } from "node:crypto"
import { test } from "node:test"

import {
  checkValues,
  makeToken,
  preflight,
  readPrivateKey,
  SetupError,
} from "./asc-preflight.mjs"

const { privateKey, publicKey } = generateKeyPairSync("ec", {
  namedCurve: "P-256",
})
const p8 = privateKey.export({ type: "pkcs8", format: "pem" })
const env = {
  ASC_KEY_ID: "2X9R4HXF34",
  ASC_ISSUER_ID: "57246542-96fe-1a63-e053-0824d011072a",
  ASC_KEY_P8: p8,
  APPLE_TEAM_ID: "A1B2C3D4E5",
}
const appId = "io.github.example.storytellerlofi"

/** A fetch stand-in that answers from `routes` and records each request. */
function fakeApi(routes) {
  const requests = []
  const fetchImpl = async (url, init) => {
    const { pathname, search } = new URL(url)
    const route = `${init.method} ${pathname}`
    requests.push({ route, search, init })
    const answer = routes[route]
    if (!answer) throw new Error(`unexpected request ${route}`)
    const { status = 200, body = {} } =
      typeof answer === "function" ? answer({ search, init }) : answer
    return new Response(JSON.stringify(body), { status })
  }
  return { fetchImpl, requests }
}

const registered = {
  body: {
    data: [
      { attributes: { identifier: `${appId}.dev`, seedId: "A1B2C3D4E5" } },
      { attributes: { identifier: appId, seedId: "A1B2C3D4E5" } },
    ],
  },
}
const withApp = {
  body: {
    data: [{ attributes: { bundleId: appId, name: "Storyteller Lofi" } }],
  },
}

test("the token is an ES256 JWT that the key's public half verifies", () => {
  const token = makeToken({
    keyId: env.ASC_KEY_ID,
    issuerId: env.ASC_ISSUER_ID,
    key: readPrivateKey(p8),
    now: 1_700_000_000_000,
  })
  const [header, payload, signature] = token.split(".")
  assert.deepEqual(JSON.parse(Buffer.from(header, "base64url")), {
    alg: "ES256",
    kid: env.ASC_KEY_ID,
    typ: "JWT",
  })
  assert.deepEqual(JSON.parse(Buffer.from(payload, "base64url")), {
    iss: env.ASC_ISSUER_ID,
    iat: 1_700_000_000,
    exp: 1_700_000_600,
    aud: "appstoreconnect-v1",
  })
  const raw = Buffer.from(signature, "base64url")
  assert.equal(raw.length, 64)
  assert.ok(
    verify(
      "sha256",
      Buffer.from(`${header}.${payload}`),
      { key: publicKey, dsaEncoding: "ieee-p1363" },
      raw,
    ),
  )
})

test("the key is accepted as pasted, with literal \\n or without its header", () => {
  assert.equal(
    readPrivateKey(p8.replaceAll("\n", "\\n")).asymmetricKeyType,
    "ec",
  )
  const body = p8
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "")
  assert.equal(readPrivateKey(body).asymmetricKeyType, "ec")
  assert.throws(() => readPrivateKey("not a key"), SetupError)
  const rsa = generateKeyPairSync("rsa", { modulusLength: 2048 })
  assert.throws(
    () =>
      readPrivateKey(rsa.privateKey.export({ type: "pkcs8", format: "pem" })),
    SetupError,
  )
})

test("swapped or mistyped secrets are named", () => {
  assert.throws(
    () =>
      checkValues({
        ...env,
        ASC_KEY_ID: env.ASC_ISSUER_ID,
        ASC_ISSUER_ID: env.ASC_KEY_ID,
      }),
    (error) =>
      error instanceof SetupError &&
      error.message.includes("ASC_KEY_ID") &&
      error.message.includes("ASC_ISSUER_ID") &&
      !error.message.includes("APPLE_TEAM_ID"),
  )
  assert.deepEqual(checkValues({ ...env, APPLE_TEAM_ID: " A1B2C3D4E5\n" }), {
    keyId: env.ASC_KEY_ID,
    issuerId: env.ASC_ISSUER_ID,
    teamId: "A1B2C3D4E5",
  })
})

test("passes when the App ID and the app exist, and changes nothing", async () => {
  const { fetchImpl, requests } = fakeApi({
    "GET /v1/bundleIds": registered,
    "GET /v1/apps": withApp,
  })
  const notes = await preflight({
    env,
    appId,
    appName: "Storyteller Lofi",
    fetchImpl,
  })
  assert.deepEqual(
    requests.map((request) => request.route),
    ["GET /v1/bundleIds", "GET /v1/apps"],
  )
  assert.match(
    requests[0].init.headers.authorization,
    /^Bearer [\w-]+\.[\w-]+\.[\w-]+$/,
  )
  assert.equal(
    new URLSearchParams(requests[0].search).get("filter[identifier]"),
    appId,
  )
  assert.equal(
    new URLSearchParams(requests[1].search).get("filter[bundleId]"),
    appId,
  )
  assert.ok(notes.some((note) => note.includes("is registered")))
})

test("registers a missing App ID, then asks for the App Store Connect app", async () => {
  const { fetchImpl, requests } = fakeApi({
    // Only the .dev variant matches the prefix filter.
    "GET /v1/bundleIds": { body: { data: [registered.body.data[0]] } },
    "POST /v1/bundleIds": ({ init }) => ({
      status: 201,
      body: {
        data: {
          attributes: {
            ...JSON.parse(init.body).data.attributes,
            seedId: "A1B2C3D4E5",
          },
        },
      },
    }),
    "GET /v1/apps": { body: { data: [] } },
  })
  await assert.rejects(
    preflight({ env, appId, appName: "Storyteller Lofi!", fetchImpl }),
    (error) =>
      error instanceof SetupError &&
      error.title === "Create the app in App Store Connect" &&
      error.message.includes(appId) &&
      error.message.includes("Registered the App ID"),
  )
  const post = requests.find(
    (request) => request.route === "POST /v1/bundleIds",
  )
  assert.deepEqual(JSON.parse(post.init.body), {
    data: {
      type: "bundleIds",
      attributes: {
        identifier: appId,
        name: "Storyteller Lofi",
        platform: "IOS",
      },
    },
  })
})

test("a refused key and a missing role get their own fixes", async () => {
  const refused = fakeApi({ "GET /v1/bundleIds": { status: 401, body: {} } })
  await assert.rejects(
    preflight({ env, appId, appName: "x", fetchImpl: refused.fetchImpl }),
    (error) => error.title === "App Store Connect refused the API key",
  )
  const forbidden = fakeApi({
    "GET /v1/bundleIds": registered,
    "GET /v1/apps": {
      status: 403,
      body: { errors: [{ code: "FORBIDDEN_ERROR", detail: "Not allowed." }] },
    },
  })
  await assert.rejects(
    preflight({ env, appId, appName: "x", fetchImpl: forbidden.fetchImpl }),
    (error) =>
      error.title === "The API key isn't allowed to do this" &&
      error.message.includes("Admin") &&
      error.message.includes("Not allowed."),
  )
  const agreement = fakeApi({
    "GET /v1/bundleIds": {
      status: 403,
      body: {
        errors: [
          {
            code: "FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED",
            detail: "A required agreement is missing or has expired.",
          },
        ],
      },
    },
  })
  await assert.rejects(
    preflight({ env, appId, appName: "x", fetchImpl: agreement.fetchImpl }),
    (error) => error.title === "An Apple agreement needs accepting",
  )
})

test("a team ID that doesn't match the App ID prefix is pointed out", async () => {
  const { fetchImpl } = fakeApi({
    "GET /v1/bundleIds": registered,
    "GET /v1/apps": withApp,
  })
  const notes = await preflight({
    env: { ...env, APPLE_TEAM_ID: "Z9Y8X7W6V5" },
    appId,
    appName: "x",
    fetchImpl,
  })
  assert.ok(notes.some((note) => note.includes("Z9Y8X7W6V5")))
})
