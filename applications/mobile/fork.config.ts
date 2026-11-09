/**
 * The Storyteller Lofi fork's own identity. See FORK.md at the repo root.
 *
 * app.config.ts builds upstream's config and then passes it through
 * `withForkIdentity` (the LOFI-FORK lines there), so the fork gets its own
 * name and bundle ID and installs next to the official Storyteller app instead
 * of replacing it. It also adds the pods for the fork's lofi music module.
 * Change the values here, never in app.config.ts, so upstream syncs keep
 * merging cleanly.
 *
 * app.config.ts imports this file with its `.ts` extension, because Expo loads
 * app.config.ts with Node's `require`, which only finds TypeScript files by
 * their full name. Keep this file to plain, erasable TypeScript (no enums or
 * namespaces) so Node can load it without a build step.
 */
import type { ConfigContext, ExpoConfig } from "expo/config"

interface ForkIdentity {
  /** The app's name on the home screen. Development builds add " (dev)". */
  name: string
  /** Expo slug. EAS and the development client's URL scheme use it. */
  slug: string
  /**
   * iOS bundle ID and Android package name. It has to be an ID that your own
   * Apple developer account can register. Development builds add ".dev".
   */
  appId: string
  /** Expo account that owns the fork's EAS project, if it ever uses EAS. */
  easOwner?: string
  /** The fork's own EAS project ID, if it ever uses EAS. */
  easProjectId?: string
}

export const forkIdentity: ForkIdentity = {
  name: "Storyteller Lofi",
  slug: "storyteller-lofi",
  appId: "io.github.melba7.storytellerlofi",
}

/**
 * The Swift package in libraries/LofiScoreKit, built from source by CocoaPods
 * for the fork's lofi music module (modules/lofi-score). Each target has a
 * podspec next to Package.swift. The path is relative to the generated `ios`
 * folder.
 */
const lofiScorePods = [
  "LofiScoreCore",
  "LofiText",
  "LofiMood",
  "LofiDirector",
  "LofiAudio",
  "LofiPlaceholders",
  "LofiScoreHost",
].map((name) => ({ name, path: "../../../libraries/LofiScoreKit" }))

type PluginEntry = NonNullable<ExpoConfig["plugins"]>[number]

interface BuildPropertiesOptions {
  ios?: { extraPods?: unknown[] }
}

/**
 * Adds the LofiScoreKit pods to expo-build-properties' `ios.extraPods`, next
 * to upstream's own extra pods.
 */
export function withLofiScorePods(plugins: PluginEntry[]): PluginEntry[] {
  return plugins.map((entry) => {
    const [name, options] = (Array.isArray(entry) ? entry : [entry]) as [
      unknown,
      BuildPropertiesOptions | undefined,
    ]
    if (name !== "expo-build-properties") return entry
    const ios = options?.ios ?? {}
    return [
      "expo-build-properties",
      {
        ...options,
        ios: {
          ...ios,
          extraPods: [...(ios.extraPods ?? []), ...lofiScorePods],
        },
      },
    ]
  })
}

export function withForkIdentity(
  upstreamConfig: (context: ConfigContext) => ExpoConfig,
): (context: ConfigContext) => ExpoConfig {
  return (context) => applyForkIdentity(upstreamConfig(context))
}

export function applyForkIdentity(config: ExpoConfig): ExpoConfig {
  // Same switch upstream uses in app.config.ts for its development variant.
  const isDev = process.env["APP_VARIANT"] === "development"
  const appId = isDev ? `${forkIdentity.appId}.dev` : forkIdentity.appId

  const result: ExpoConfig = {
    ...config,
    name: isDev ? `${forkIdentity.name} (dev)` : forkIdentity.name,
    slug: forkIdentity.slug,
    ios: { ...config.ios, bundleIdentifier: appId },
    android: { ...config.android, package: appId },
    plugins: withLofiScorePods(config.plugins ?? []),
  }

  // Upstream's EAS account and project belong to upstream. Drop them unless
  // the fork has its own.
  if (forkIdentity.easOwner) {
    result.owner = forkIdentity.easOwner
  } else {
    delete result.owner
  }
  const extra = { ...config.extra }
  delete extra["eas"]
  if (forkIdentity.easProjectId) {
    extra["eas"] = { projectId: forkIdentity.easProjectId }
  }
  result.extra = extra

  // The URL scheme deliberately stays upstream's `storyteller`: Storyteller
  // servers send the login callback to storyteller://settings, and iOS hands
  // that callback straight to the app that started the login, so the fork can
  // share the scheme with the official app.
  return result
}
