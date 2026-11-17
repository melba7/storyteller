// LOFI-FORK: the podcasts section's background refresh (see FORK.md).
//
// Imported while the app starts (store/store.ts), also when iOS starts the app in the
// background, because a task has to be defined before it can run. It defines the task, asks
// iOS to run it now and then, and refreshes when the app comes to the front. iOS decides when
// the task runs (often overnight). The work is in automaticRun.ts, loaded only when needed so
// the start stays light.
import * as BackgroundTask from "expo-background-task"
import * as TaskManager from "expo-task-manager"
import { AppState } from "react-native"

import { Podcasts } from "./index"

const TASK = "podcasts-background-refresh"
/** Minutes. iOS treats this as a hint. */
const MINIMUM_INTERVAL = 60
/** A moment after the app opens, so the screens are not slowed down. */
const FOREGROUND_DELAY_MS = 3000

TaskManager.defineTask(TASK, async () => {
  try {
    const { runAutomatic } = await import("./automaticRun")
    await runAutomatic()
    return BackgroundTask.BackgroundTaskResult.Success
  } catch (cause) {
    console.warn("The podcasts background refresh failed", cause)
    return BackgroundTask.BackgroundTaskResult.Failed
  }
})

/** Saves the bookmarks the headphones made while JavaScript wasn't running. */
async function importBookmarks() {
  try {
    const { importPendingBookmarks } = await import("./dbBookmarks")
    await importPendingBookmarks()
  } catch (cause) {
    console.warn("Couldn't import the headphone bookmarks", cause)
  }
}

async function refreshInForeground() {
  await importBookmarks()
  try {
    const { runIfDue } = await import("./automaticRun")
    await runIfDue()
  } catch (cause) {
    console.warn("The podcasts refresh failed", cause)
  }
}

if (Podcasts !== null) {
  BackgroundTask.registerTaskAsync(TASK, {
    minimumInterval: MINIMUM_INTERVAL,
  }).catch((cause: unknown) => {
    console.warn("Couldn't register the podcasts background task", cause)
  })

  // A bookmark made with the headphones while the app is open is saved at once.
  Podcasts.addListener("onBookmarksPending", () => {
    void importBookmarks()
  })

  const later = () => setTimeout(refreshInForeground, FOREGROUND_DELAY_MS)
  if (AppState.currentState === "active") later()
  AppState.addEventListener("change", (state) => {
    if (state === "active") later()
  })
}
