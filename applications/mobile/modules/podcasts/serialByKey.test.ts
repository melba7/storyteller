// LOFI-FORK: the podcasts section's tests (see FORK.md).
import { describe, expect, it } from "vitest"

import { serialByKey } from "./serialByKey"

describe("serialByKey", () => {
  it("never runs two jobs for one key at once, in the order asked", async () => {
    const run = serialByKey()
    const log: string[] = []
    const job = (name: string) => async () => {
      log.push(`${name} start`)
      await new Promise((resolve) => setTimeout(resolve, 5))
      log.push(`${name} end`)
      return name
    }
    const results = await Promise.all([
      run("a", job("1")),
      run("a", job("2")),
      run("b", job("3")),
    ])
    expect(results).toEqual(["1", "2", "3"])
    expect(log.indexOf("1 end")).toBeLessThan(log.indexOf("2 start"))
    expect(log.indexOf("3 start")).toBeLessThan(log.indexOf("1 end"))
  })

  it("carries on after a job fails, and gives that job its error", async () => {
    const run = serialByKey()
    const failed = run("a", () => Promise.reject(new Error("no")))
    const next = run("a", () => Promise.resolve("ok"))
    await expect(failed).rejects.toThrow("no")
    await expect(next).resolves.toBe("ok")
  })
})
