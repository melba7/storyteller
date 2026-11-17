// LOFI-FORK: the fork's app config adds the LofiScoreKit pods (see FORK.md).
import { afterEach, describe, expect, it, vi } from "vitest"

import {
  applyForkIdentity,
  forkIdentity,
  soundEdition,
  withLofiScorePods,
} from "@/fork.config.ts"

describe("withLofiScorePods", () => {
  it("adds the pods next to upstream's extra pods", () => {
    const plugins = withLofiScorePods([
      "expo-router",
      [
        "expo-build-properties",
        {
          ios: { deploymentTarget: "16.4", extraPods: [{ name: "Minizip" }] },
          android: { compileSdkVersion: 36 },
        },
      ],
    ])
    expect(plugins[0]).toBe("expo-router")
    const [, options] = plugins[1] as [
      string,
      {
        ios: { deploymentTarget: string; extraPods: { name: string }[] }
        android: unknown
      },
    ]
    expect(options.ios.deploymentTarget).toBe("16.4")
    expect(options.android).toEqual({ compileSdkVersion: 36 })
    expect(options.ios.extraPods.map((pod) => pod.name)).toEqual([
      "Minizip",
      "LofiScoreCore",
      "LofiText",
      "LofiMood",
      "LofiAudioCore",
      "LofiAtmosphere",
      "LofiScoreHost",
      "PodcastFeed",
      "PodcastPlayback",
      "PodcastDownloads",
      "PodcastTranscripts",
      "PodcastSpeech",
      "PodcastAds",
      "PodcastAdsOnDevice",
      "PodcastChapters",
    ])
    expect(options.ios.extraPods[1]).toEqual({
      name: "LofiScoreCore",
      path: "../../../libraries/LofiScoreKit",
    })
  })

  it("adds the podcast feed reader's, player rules', downloads', transcripts', speech, ads and chapters pods from PodcastKit", () => {
    const plugins = withLofiScorePods([
      ["expo-build-properties", { ios: { extraPods: [] } }],
    ])
    const [, options] = plugins[0] as [
      string,
      { ios: { extraPods: { name: string; path: string }[] } },
    ]
    expect(options.ios.extraPods.slice(-8)).toEqual([
      { name: "PodcastFeed", path: "../../../libraries/PodcastKit" },
      { name: "PodcastPlayback", path: "../../../libraries/PodcastKit" },
      { name: "PodcastDownloads", path: "../../../libraries/PodcastKit" },
      { name: "PodcastTranscripts", path: "../../../libraries/PodcastKit" },
      { name: "PodcastSpeech", path: "../../../libraries/PodcastKit" },
      { name: "PodcastAds", path: "../../../libraries/PodcastKit" },
      { name: "PodcastAdsOnDevice", path: "../../../libraries/PodcastKit" },
      { name: "PodcastChapters", path: "../../../libraries/PodcastKit" },
    ])
  })

  it("leaves other plugins alone", () => {
    expect(withLofiScorePods(["expo-image", ["expo-font", {}]])).toEqual([
      "expo-image",
      ["expo-font", {}],
    ])
  })
})

describe("soundEdition", () => {
  it("is personal unless the build asks to publish", () => {
    expect(soundEdition(undefined)).toBe("personal")
    expect(soundEdition("")).toBe("personal")
    expect(soundEdition("personal")).toBe("personal")
    expect(soundEdition(" Publish ")).toBe("publish")
  })

  it("goes into the Info.plist next to upstream's keys", () => {
    const config = applyForkIdentity({
      name: "Storyteller",
      slug: "storyteller",
      ios: {
        bundleIdentifier: "dev.smoores.Storyteller",
        infoPlist: { UIBackgroundModes: ["audio"] },
      },
    })
    expect(config.ios?.infoPlist).toEqual({
      UIBackgroundModes: ["audio", "processing"],
      BGTaskSchedulerPermittedIdentifiers: [
        `${forkIdentity.appId}.soundsImport`,
        `${forkIdentity.appId}.podcastTranscribe`,
        `${forkIdentity.appId}.podcastAds`,
      ],
      LofiScoreSoundEdition: soundEdition(),
      NSAppTransportSecurity: { NSAllowsArbitraryLoadsForMedia: true },
    })
  })

  it("lets episodes play over plain http and keeps upstream's transport keys", () => {
    const config = applyForkIdentity({
      name: "Storyteller",
      slug: "storyteller",
      ios: {
        infoPlist: {
          NSAppTransportSecurity: {
            NSAllowsLocalNetworking: true,
            NSAllowsArbitraryLoadsForMedia: false,
          },
        },
      },
    })
    expect(config.ios?.infoPlist?.["NSAppTransportSecurity"]).toEqual({
      NSAllowsLocalNetworking: true,
      NSAllowsArbitraryLoadsForMedia: true,
    })
  })

  it("lets the sounds import finish in the background, next to upstream's task", () => {
    const config = applyForkIdentity({
      name: "Storyteller",
      slug: "storyteller",
      ios: {
        infoPlist: {
          UIBackgroundModes: ["audio", "processing"],
          BGTaskSchedulerPermittedIdentifiers: ["upstream.task"],
        },
      },
    })
    expect(config.ios?.infoPlist?.["UIBackgroundModes"]).toEqual([
      "audio",
      "processing",
    ])
    expect(
      config.ios?.infoPlist?.["BGTaskSchedulerPermittedIdentifiers"],
    ).toEqual([
      "upstream.task",
      `${forkIdentity.appId}.soundsImport`,
      `${forkIdentity.appId}.podcastTranscribe`,
      `${forkIdentity.appId}.podcastAds`,
    ])
  })

  describe("in a TestFlight build", () => {
    afterEach(() => {
      vi.unstubAllEnvs()
    })

    it("keeps the build number and signing team next to it", () => {
      vi.stubEnv("FORK_BUILD_NUMBER", "42")
      vi.stubEnv("APPLE_TEAM_ID", "TEAM123456")
      vi.stubEnv("LOFI_SOUND_EDITION", "publish")
      const config = applyForkIdentity({
        name: "Storyteller",
        slug: "storyteller",
        ios: { infoPlist: { UIBackgroundModes: ["audio"] } },
      })
      expect(config.ios?.buildNumber).toBe("42")
      expect(config.ios?.appleTeamId).toBe("TEAM123456")
      expect(config.ios?.infoPlist).toMatchObject({
        LofiScoreSoundEdition: "publish",
      })
    })
  })
})

describe("applyForkIdentity's name", () => {
  afterEach(() => {
    vi.unstubAllEnvs()
  })

  it("is Storyteller+ on the home screen, whatever upstream calls the app", () => {
    vi.stubEnv("APP_VARIANT", "")
    const config = applyForkIdentity({
      name: "Storyteller",
      slug: "storyteller",
    })
    expect(config.name).toBe("Storyteller+")
  })

  it("adds (dev) for development builds", () => {
    vi.stubEnv("APP_VARIANT", "development")
    const config = applyForkIdentity({
      name: "Storyteller",
      slug: "storyteller",
    })
    expect(config.name).toBe("Storyteller+ (dev)")
  })
})
