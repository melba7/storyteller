// LOFI-FORK: a book's lofi score (Claude's mood track and the atmosphere cues
// the Mac makes), kept inside the read-aloud EPUB so the phone gets it with
// the book (see FORK.md). Nothing upstream reads it.
import { withHasPermission } from "@/auth/auth"
import { getBook, getBookUuid } from "@/database/books"
import { logger } from "@/logging"

import { SCORE_FORMAT, describeScore, readScore, writeScore } from "./score"

export const dynamic = "force-dynamic"

const MAX_SCORE_BYTES = 32 * 1024 * 1024

type Params = Promise<{
  bookId: string
}>

/**
 * @summary Get a book's lofi score
 * @desc The score (`{"format":1,"mood":…,"atmosphere":…}`) kept inside the
 *       book's read-aloud EPUB, as the Storyteller Lofi app reads it. 404 when
 *       the book has no read-aloud EPUB or no score yet.
 */
export const GET = withHasPermission<Params>("bookRead", {
  allowBasicAuth: true,
})(async (request, context) => {
  const { bookId } = await context.params
  const bookUuid = await getBookUuid(bookId)
  const book = await getBook(bookUuid, request.auth.user.id)
  if (!book) {
    return Response.json(
      { message: `Could not find book with id ${bookId}` },
      { status: 404 },
    )
  }
  const filepath = book.readaloud?.filepath
  if (!filepath?.endsWith(".epub")) {
    return Response.json(
      { message: `Book with id ${bookId} has no read-aloud EPUB` },
      { status: 404 },
    )
  }

  let score: Buffer | null
  try {
    score = await readScore(filepath)
  } catch (error) {
    logger.error({ msg: "could not read the lofi score", err: error })
    return Response.json(
      { message: `Could not open the read-aloud EPUB of book ${bookId}` },
      { status: 404 },
    )
  }
  if (!score) {
    return Response.json(
      { message: `Book with id ${bookId} has no lofi score yet` },
      { status: 404 },
    )
  }
  return new Response(new Uint8Array(score), {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      "Content-Length": `${score.byteLength}`,
      "Cache-Control": "no-store",
    },
  })
})

/**
 * @summary Put a book's lofi score inside its read-aloud EPUB
 * @desc The body is the score file the Mac's tools make
 *       (`{"format":1,"mood":…,"atmosphere":…}`, at least one part). It
 *       replaces any score already in the book. The EPUB is rewritten, so
 *       readers that already have the book fetch the score with GET instead.
 */
export const PUT = withHasPermission<Params>("bookUpdate")(async (
  request,
  context,
) => {
  const { bookId } = await context.params
  const bookUuid = await getBookUuid(bookId)
  const book = await getBook(bookUuid, request.auth.user.id)
  if (!book) {
    return Response.json(
      { message: `Could not find book with id ${bookId}` },
      { status: 404 },
    )
  }
  const filepath = book.readaloud?.filepath
  if (!filepath?.endsWith(".epub")) {
    return Response.json(
      { message: `Book with id ${bookId} has no read-aloud EPUB` },
      { status: 409 },
    )
  }

  const declared = Number.parseInt(
    request.headers.get("Content-Length") ?? "0",
    10,
  )
  if (declared > MAX_SCORE_BYTES) {
    return Response.json({ message: "The score is too large" }, { status: 413 })
  }
  const text = await request.text()
  if (text.length > MAX_SCORE_BYTES) {
    return Response.json({ message: "The score is too large" }, { status: 413 })
  }
  const shape = describeScore(text)
  if (!shape) {
    return Response.json(
      {
        message: `Expected a format ${SCORE_FORMAT} score with a mood track or an atmosphere track`,
      },
      { status: 400 },
    )
  }

  try {
    await writeScore(filepath, text)
  } catch (error) {
    logger.error({ msg: "could not write the lofi score", err: error })
    return Response.json(
      {
        message: `Could not put the score inside the read-aloud EPUB of book ${bookId}`,
      },
      { status: 500 },
    )
  }
  logger.info(
    `lofi score saved in book ${bookUuid} (mood: ${shape.mood ? "yes" : "no"}, atmosphere: ${shape.atmosphere ? "yes" : "no"})`,
  )
  return Response.json({ message: "saved", ...shape })
})
