// LOFI-FORK: the fork's app config adds the LofiScoreKit pods (see FORK.md).
import { afterEach, describe, expect, it, vi } from "vitest"

import {
  applyForkIdentity,
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
    ])
    expect(options.ios.extraPods[1]).toEqual({
      name: "LofiScoreCore",
      path: "../../../libraries/LofiScoreKit",
    })
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
      UIBackgroundModes: ["audio"],
      LofiScoreSoundEdition: soundEdition(),
    })
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
      expect(config.ios?.infoPlist).toEqual({
        UIBackgroundModes: ["audio"],
        LofiScoreSoundEdition: "publish",
      })
    })
  })
})
