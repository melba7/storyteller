// LOFI-FORK: lets the atmosphere sounds follow the pages while you read a
// readaloud book on screen with the narration stopped (see FORK.md).
// store/store.ts imports this file once, for its listeners.
import { AppState } from "react-native"

import { logger } from "@/logger"
import { LofiScore } from "@/modules/lofi-score"
import { ReaderSession } from "@/modules/lofi-score/readerSession"
import { getClip } from "@/modules/readium"
import { bookLocatorChanged } from "@/store/actions"
import { startAppListening } from "@/store/listeners/listenerMiddleware"
import { localApi } from "@/store/localApi"
import {
  getCurrentlyPlayingBookUuid,
  getCurrentlyPlayingFormat,
  getIsPlaying,
} from "@/store/selectors/bookshelfSelectors"

const session = new ReaderSession(() => {
  void LofiScore?.readerStopped()
})

/**
 * The reader is showing this book (it opened, or the app came back to it).
 * The sounds wait for the first page turn: the page the book opens at does
 * not start them.
 */
export function readerShown(bookUuid: string) {
  session.shown(bookUuid, Date.now())
}

/**
 * The reader went away (the book closed, or the app left it): the sounds that
 * follow the pages stop, instead of playing on until they time out. The
 * narration's sounds are not affected.
 */
export function readerHidden() {
  session.hidden(Date.now())
}

/**
 * The page turned while the narration is stopped: tell the sounds which
 * sentence now tops the page, found the same way the app keeps the audio in
 * step with the page. The scene is placed there, never further into the page.
 */
startAppListening({
  actionCreator: bookLocatorChanged,
  effect: async (action, listenerApi) => {
    if (!LofiScore) return
    const { bookUuid, locator, timestamp } = action.payload
    // The reader reporting the page it opened at is not a page turn.
    if (!session.isPageTurn(bookUuid, timestamp)) return
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
      logger.error(`Lofi atmosphere, following the page: ${String(error)}`)
    }
  },
})

// Leaving the app stops the sounds that follow the pages (the narration's
// sounds carry on in the background as before).
AppState.addEventListener("change", (state) => {
  if (state === "background") void LofiScore?.readerStopped()
})
