// LOFI-FORK: brings a book's score (its mood track and atmosphere cues) from
// the Storyteller server when the phone has none for the open book (see
// FORK.md). The fork's server keeps each score inside the read-aloud EPUB and
// serves it at GET /api/v2/books/<id>/lofi-score; a server without the route
// answers 404 and is asked again an hour later.
import { skipToken } from "@reduxjs/toolkit/query"
import { useEffect } from "react"

import { logger } from "@/logger"
import { LofiScore, type LofiMusicStatus } from "@/modules/lofi-score"
import { bookNeedingScore } from "@/modules/lofi-score/status"
import {
  useGetBookQuery,
  useGetServerAccessTokenQuery,
  useGetServerQuery,
} from "@/store/localApi"
import { type UUID } from "@/uuid"

/** When each book was last asked for, so a book without a score is asked once an hour. */
const askedAt = new Map<string, number>()
const ASK_AGAIN_AFTER = 60 * 60 * 1000

/** For tests: forget when books were asked for. */
export function resetScoreRequests() {
  askedAt.clear()
}

/**
 * Fetches the score of the book the music is following and hands it to the
 * native module, which keeps it with the book and reads the book again.
 */
export async function fetchBookScore(
  bookUuid: string,
  baseUrl: string,
  accessToken: string,
  fetchImpl: typeof fetch = fetch,
): Promise<"installed" | "none" | "failed"> {
  if (!LofiScore) return "failed"
  const url = `${baseUrl.replace(/\/$/, "")}/api/v2/books/${bookUuid}/lofi-score`
  const response = await fetchImpl(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  })
  if (response.status === 404) return "none"
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`)
  }
  await LofiScore.installBookScore(bookUuid, await response.text())
  return "installed"
}

export function useBookScore(
  status: LofiMusicStatus | null,
  refresh: () => Promise<void> | void,
) {
  // The native module names books by the app's uuid, the server's for synced books.
  const bookUuid = bookNeedingScore(status) as UUID | null
  const { data: book } = useGetBookQuery(
    bookUuid ? { uuid: bookUuid } : skipToken,
  )
  const serverUuid = book?.serverUuid ?? null
  const { data: server } = useGetServerQuery(
    serverUuid ? { uuid: serverUuid } : skipToken,
  )
  const { data: accessToken } = useGetServerAccessTokenQuery(
    serverUuid ? { serverUuid } : skipToken,
  )

  useEffect(() => {
    if (!bookUuid || !server || !accessToken) return
    const now = Date.now()
    const last = askedAt.get(bookUuid)
    if (last !== undefined && now - last < ASK_AGAIN_AFTER) return
    askedAt.set(bookUuid, now)
    void (async () => {
      try {
        const result = await fetchBookScore(
          bookUuid,
          server.baseUrl,
          accessToken,
        )
        if (result === "installed") {
          logger.info(`Lofi score for book ${bookUuid} fetched from the server`)
          await refresh()
        }
      } catch (error) {
        // Ask again at the next chance rather than in an hour.
        askedAt.delete(bookUuid)
        logger.error(`Lofi score for book ${bookUuid}: ${String(error)}`)
      }
    })()
  }, [bookUuid, server, accessToken, refresh])
}
