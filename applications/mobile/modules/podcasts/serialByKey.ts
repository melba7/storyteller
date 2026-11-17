// LOFI-FORK: the podcasts section's one-at-a-time jobs (see FORK.md).

/**
 * Returns a runner that never runs two jobs for the same key at the same time: each waits for
 * the one before it, whether that one worked or failed. Jobs for other keys do not wait.
 */
export function serialByKey() {
  const last = new Map<string, Promise<unknown>>()
  return function run<T>(key: string, job: () => Promise<T>): Promise<T> {
    const result = (last.get(key) ?? Promise.resolve())
      .catch(() => {})
      .then(job)
    const tail = result.catch(() => {})
    last.set(key, tail)
    void tail.then(() => {
      if (last.get(key) === tail) last.delete(key)
    })
    return result
  }
}
