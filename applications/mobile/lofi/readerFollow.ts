// LOFI-FORK: lets the lofi music follow the pages while you read a readaloud
// book on screen with the narration stopped (see FORK.md). store/store.ts
// imports this file once, for its listeners.
import { AppState } from "react-native"

import { logger } from "@/logger"
import { LofiScore } from "@/modules/lofi-score"
import { getClip } from "@/modules/readium"
import { bookLocatorChanged } from "@/store/actions"
import { startAppListening } from "@/store/listeners/listenerMiddleware"
import { localApi } from "@/store/localApi"
import {
  getCurrentlyPlayingBookUuid,
  getCurrentlyPlayingFormat,
  getIsPlaying,
} from "@/store/selectors/bookshelfSelectors"

/**
 * The page moved while the narration is stopped: tell the music which sentence
 * now tops the page, found the same way the app keeps the audio in step with
 * the page. The music judges the mood from there, never from the rest of the
 * page.
 */
startAppListening({
  actionCreator: bookLocatorChanged,
  effect: async (action, listenerApi) => {
    if (!LofiScore) return
    const { bookUuid, locator } = action.payload
    const state = listenerApi.getState()
    if (getIsPlaying(state)) return
    if (getCurrentlyPlayingBookUuid(state) !== bookUuid) return
    const format = getCurrentlyPlayingFormat(state)
    if (format !== "readaloud") return

    // Page turns come quickly; only the latest one matters.
    listenerApi.cancelActiveListeners()
    await listenerApi.delay(300)

    try {
      const book = await listenerApi
        .dispatch(
          localApi.endpoints.getBook.initiate(
            { uuid: bookUuid },
            { subscribe: false },
          ),
        )
        .unwrap()
      if (!book) return
      const positions = await listenerApi
        .dispatch(
          localApi.endpoints.getBookPositions.initiate(
            { bookUuid, format },
            { forceRefetch: false, subscribe: false },
          ),
        )
        .unwrap()
      const clip = await getClip(book, format, locator, positions)
      if (!clip) return
      await LofiScore.readerReached(bookUuid, clip.relativeUrl, clip.start)
    } catch (error) {
      logger.error(`Lofi music, following the page: ${String(error)}`)
    }
  },
})

// Leaving the app stops the music that follows the pages (the narration's
// music carries on in the background as before).
AppState.addEventListener("change", (state) => {
  if (state === "background") void LofiScore?.readerStopped()
})
