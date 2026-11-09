// LOFI-FORK: the fork's app config adds the LofiScoreKit pods (see FORK.md).
import { describe, expect, it } from "vitest"

import { withLofiScorePods } from "../../fork.config.ts"

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
      "LofiDirector",
      "LofiAudio",
      "LofiPlaceholders",
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
