// LOFI-FORK: when the music that follows the pages may start and when it
// stops (see FORK.md).

/**
 * How long after the reader appears its page reports count as the reader
 * settling on the page it opened at, not as page turns. Once its page has
 * loaded, the reader can report the page it opened at, which takes a second
 * or two. Turning a page this soon after opening is rare, and a turn that
 * falls in this time only means the music starts on the next one.
 */
export const readerSettleMs = 5000

/**
 * A reader that goes away and comes back within this time is the same
 * reader. Its toolbar moved (the phone turned sideways), and the book did
 * not close and open again.
 */
export const readerMoveMs = 1000

type Timers = {
  later(action: () => void): unknown
  cancel(handle: unknown): void
}

const realTimers: Timers = {
  later: (action) => setTimeout(action, 0),
  cancel: (handle) => {
    clearTimeout(handle as ReturnType<typeof setTimeout>)
  },
}

/**
 * The reader's side of the music while reading, with the narration stopped.
 * The music starts on the first page turn, not when a book opens, and it stops
 * when the reader goes away.
 */
export class ReaderSession {
  private bookUuid: string | null = null
  private openedAt: number | null = null
  private hiddenAt: number | null = null
  private pendingStop: unknown = undefined

  constructor(
    private readonly stopMusic: () => void,
    private readonly timers: Timers = realTimers,
  ) {}

  /** The reader is showing this book: it opened, or the app came back to it. */
  shown(bookUuid: string, now: number): void {
    const moved =
      this.hiddenAt !== null &&
      now - this.hiddenAt < readerMoveMs &&
      this.bookUuid === bookUuid
    this.hiddenAt = null
    if (this.pendingStop !== undefined) {
      this.timers.cancel(this.pendingStop)
      this.pendingStop = undefined
      // Another book, or the stop was held up while the app was away.
      if (!moved) this.stopMusic()
    }
    if (moved) return
    this.bookUuid = bookUuid
    this.openedAt = now
  }

  /**
   * The reader went away: the music that follows the pages stops, unless the
   * reader shows again at once.
   */
  hidden(now: number): void {
    this.hiddenAt = now
    if (this.pendingStop !== undefined) return
    this.pendingStop = this.timers.later(() => {
      this.pendingStop = undefined
      this.stopMusic()
    })
  }

  /** True when a page report from this book, at this time, is a page turn. */
  isPageTurn(bookUuid: string, reportedAt: number): boolean {
    if (this.openedAt === null) return true
    if (this.bookUuid !== bookUuid) return false
    return reportedAt - this.openedAt >= readerSettleMs
  }
}
