// LOFI-FORK: the podcasts section's show colours (see FORK.md).
import { describe, expect, it, vi } from "vitest"

import { ensureArtworkColor } from "./artworkColor"

const show = (
  id: string,
  color: string | null = null,
  image = "http://i/a",
) => ({
  id,
  imageUrl: image,
  artworkColor: color,
})

function deps(measured: string | null = "#336699") {
  return {
    measure: vi.fn(() => Promise.resolve(measured)),
    save: vi.fn(() => Promise.resolve()),
  }
}

describe("ensureArtworkColor", () => {
  it("measures the artwork and saves the colour", async () => {
    const d = deps()
    expect(await ensureArtworkColor(show("a1"), d)).toBe("#336699")
    expect(d.measure).toHaveBeenCalledWith("http://i/a")
    expect(d.save).toHaveBeenCalledWith("a1", "#336699")
  })

  it("skips when the colour is already set", async () => {
    const d = deps()
    expect(await ensureArtworkColor(show("a2", "#112233"), d)).toBe("#112233")
    expect(d.measure).not.toHaveBeenCalled()
    expect(d.save).not.toHaveBeenCalled()
  })

  it("does nothing for a show without artwork or without a native module", async () => {
    const d = deps()
    expect(await ensureArtworkColor(show("a3", null, ""), d)).toBeNull()
    expect(await ensureArtworkColor(show("a4"), null)).toBeNull()
    expect(d.measure).not.toHaveBeenCalled()
  })

  it("saves nothing when the artwork has no colour", async () => {
    const d = deps(null)
    expect(await ensureArtworkColor(show("a5"), d)).toBeNull()
    expect(d.save).not.toHaveBeenCalled()
  })

  it("measures once when two screens ask at the same time", async () => {
    const d = deps()
    const [first, second] = await Promise.all([
      ensureArtworkColor(show("a6"), d),
      ensureArtworkColor(show("a6"), d),
    ])
    expect(first).toBe("#336699")
    expect(second).toBe("#336699")
    expect(d.measure).toHaveBeenCalledTimes(1)
    expect(d.save).toHaveBeenCalledTimes(1)
  })

  it("lets a later call try again after a failure", async () => {
    const d = deps()
    d.measure.mockRejectedValueOnce(new Error("offline"))
    await expect(ensureArtworkColor(show("a7"), d)).rejects.toThrow("offline")
    expect(await ensureArtworkColor(show("a7"), d)).toBe("#336699")
  })
})
