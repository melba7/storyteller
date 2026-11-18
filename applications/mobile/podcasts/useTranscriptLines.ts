// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useEffect, useState } from "react"

import { type StoredEpisode } from "@/modules/podcasts/library"
import { player } from "@/modules/podcasts/playerInstance"
import {
  type TranscriptResult,
  loadTranscript,
} from "@/modules/podcasts/transcriptLoad"

import { useTranscript } from "./useTranscripts"

export type TranscriptState =
  | { status: "loading" }
  | ({ status: "done" } & TranscriptResult)

/**

 * The transcript of an episode (the phone's own when it has one, else the feed's), loaded when the screen using it opens and again when the
 * phone's own transcript changes state or percent (it may have grown or just finished). Mount it once per
 * episode (give the screen the episode's id as its key).
 */
export function useTranscriptLines(
  episode: Pick<StoredEpisode, "id" | "transcriptUrl" | "transcriptType">,
): TranscriptState {
  const device = useTranscript(episode.id)
  const [state, setState] = useState<TranscriptState>({ status: "loading" })
  const deviceState = device?.state ?? null
  // While it is transcribing, the percent changes once per saved piece: read the lines again.
  const percent =
    device?.state === "transcribing" ? (device.percent ?? null) : null
  useEffect(() => {
    let live = true
    // Where the listener is now, so a transcript still being made is used if it reaches it.
    const view = player.getView()
    loadTranscript({
      playhead: view.episode?.id === episode.id ? view.position : null,
      id: episode.id,
      transcriptUrl: episode.transcriptUrl,
      transcriptType: episode.transcriptType,
      device,
    }).then(
      (result) => {
        if (live) setState({ status: "done", ...result })
      },
      () => {
        if (live) {
          setState({
            status: "done",
            lines: null,
            reason: "The transcript couldn't be opened.",
          })
        }
      },
    )
    return () => {
      live = false
    }
    // The device transcript matters through its state and, while transcribing, its percent.
    // oxlint-disable-next-line react-hooks/exhaustive-deps
  }, [
    episode.id,
    episode.transcriptUrl,
    episode.transcriptType,
    deviceState,
    percent,
  ])
  return state
}
