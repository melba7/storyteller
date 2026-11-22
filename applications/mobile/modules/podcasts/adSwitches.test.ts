// LOFI-FORK: the podcasts section's ads (see FORK.md).
import { describe, expect, it } from "vitest"

import { AD_SWITCHES } from "./adSwitches"
import { DEFAULT_AD_SKIP_SETTINGS } from "./ads"

describe("AD_SWITCHES", () => {
  it("has one row for each switch, in the order of the screen", () => {
    expect(AD_SWITCHES.map((row) => row.title)).toEqual([
      "Sponsor ads",
      "The hosts' own plugs",
      "Promos",
      "Intros and credits",
    ])
    expect(AD_SWITCHES.map((row) => row.key).sort()).toEqual(
      Object.keys(DEFAULT_AD_SKIP_SETTINGS).sort(),
    )
  })

  it("says in a plain line what each one skips", () => {
    expect(AD_SWITCHES[1]?.body).toContain("Patreon")
    expect(AD_SWITCHES[2]?.body).toContain("live events")
    for (const row of AD_SWITCHES) expect(row.body.length).toBeGreaterThan(20)
  })
})
