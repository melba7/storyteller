// LOFI-FORK: the podcasts section's change notice (see FORK.md).
//
// Screens read the library through hooks. After the library changes (a show added,
// refreshed or removed), whoever changed it calls notifyLibraryChanged and every
// open screen reads again.

type Listener = () => void

const listeners = new Set<Listener>()
let version = 0

/** Starts listening. Returns the function that stops. */
export function onLibraryChanged(listener: Listener): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

/** How many times the library has changed since the app started. */
export function libraryVersion(): number {
  return version
}

export function notifyLibraryChanged(): void {
  version += 1
  for (const listener of [...listeners]) listener()
}
