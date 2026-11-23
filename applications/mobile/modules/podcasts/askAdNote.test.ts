// LOFI-FORK: the podcasts section's question note (see FORK.md).
//
// There is no screen in a test, so the note's parts are replaced by plain names and the tree of
// elements it returns is read.
import { describe, expect, it, vi } from "vitest"

import { sheetColors } from "./playerSheet"

vi.mock("react-native", () => ({ Pressable: "Pressable", View: "View" }))
vi.mock("@/components/ui/text", () => ({ Text: "Text" }))
vi.mock("@/podcasts/useAskNote", () => ({
  useAskNote: () => null,
  pressAskAnswer: () => {},
}))

type Element = { type: unknown; props: Record<string, unknown> }

/** Every element in the tree, and every piece of text. */
function walk(node: unknown, found: { elements: Element[]; texts: string[] }) {
  if (Array.isArray(node)) {
    for (const child of node) walk(child, found)
  } else if (typeof node === "string") {
    found.texts.push(node)
  } else if (typeof node === "object" && node !== null) {
    const element = node as Element
    found.elements.push(element)
    walk(element.props["children"], found)
  }
  return found
}

/** Taps a button the way the screen does: by calling its onPress. */
function press(button: Element | undefined) {
  const onPress = button?.props["onPress"]
  if (typeof onPress !== "function") throw new Error("no button to press")
  onPress()
}

async function render(onAnswer = vi.fn()) {
  const { AskAdNoteView } = await import("@/podcasts/AskAdNote")
  const tree = walk(AskAdNoteView({ sheet: sheetColors(null), onAnswer }), {
    elements: [],
    texts: [],
  })
  const buttons = tree.elements.filter(
    (element) => element.type === "Pressable",
  )
  return { tree, buttons, onAnswer }
}

describe("AskAdNoteView", () => {
  it("asks Ad? Skip", async () => {
    const { tree } = await render()
    expect(tree.texts).toContain("Ad? Skip")
  })

  it("has the two buttons, Not an ad and then Skip (the main one last, as Undo is)", async () => {
    const { buttons } = await render()
    expect(buttons).toHaveLength(2)
    expect(buttons.map((button) => button.props["accessibilityRole"])).toEqual([
      "button",
      "button",
    ])
    const labels = buttons.map(
      (button) => walk(button, { elements: [], texts: [] }).texts,
    )
    expect(labels).toEqual([["Not an ad"], ["Skip"]])
  })

  it("gives each button a label a screen reader can say", async () => {
    const { buttons } = await render()
    for (const button of buttons) {
      expect(String(button.props["accessibilityLabel"]).length).toBeGreaterThan(
        3,
      )
    }
  })

  it("answers yes for Skip and no for Not an ad", async () => {
    const { buttons, onAnswer } = await render()
    const [not, skip] = buttons
    press(skip)
    expect(onAnswer).toHaveBeenLastCalledWith(true)
    press(not)
    expect(onAnswer).toHaveBeenLastCalledWith(false)
    expect(onAnswer).toHaveBeenCalledTimes(2)
  })
})
