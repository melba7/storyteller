// LOFI-FORK: the lofi music button in the player's toolbar, and the panel it
// opens (see FORK.md).
import { Music } from "lucide-react-native"
import { useEffect, useState } from "react"
import { Modal, Pressable, View } from "react-native"
import { useSafeAreaInsets } from "react-native-safe-area-context"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { cn } from "@/lib/utils"
import { useAppSelector } from "@/store/appState"
import { getCurrentlyPlayingBookUuid } from "@/store/selectors/bookshelfSelectors"

import { LofiMusicControls } from "./LofiMusicControls"
import { readerHidden, readerShown } from "./readerFollow"
import { useLofiMusic } from "./useLofiMusic"

type Props = {
  /** The toolbar's screen: the reader ("text") or the listening screen. */
  mode: "audio" | "text"
}

/**
 * Opens the music panel: on and off, the music's volume under the voice, and
 * the car setting. Shown for readaloud books, where there is text to follow.
 */
export function LofiMusicToolbarItem({ mode }: Props) {
  const [open, setOpen] = useState(false)
  const music = useLofiMusic(open ? 1500 : 15000)
  const insets = useSafeAreaInsets()

  const bookUuid = useAppSelector(getCurrentlyPlayingBookUuid)

  // The reader's toolbar comes and goes with the reader. The music that
  // follows the pages waits for the first page turn after the book opens, and
  // stops when the book closes.
  useEffect(() => {
    if (mode !== "text" || !bookUuid) return
    readerShown(bookUuid)
    return () => {
      readerHidden()
    }
  }, [mode, bookUuid])

  if (!music.available) return null
  const enabled = music.status?.enabled ?? true

  return (
    <>
      <Button
        accessibilityLabel={
          enabled
            ? "Lofi music is on. Adjust it"
            : "Lofi music is off. Adjust it"
        }
        variant="ghost"
        size="icon"
        className="h-10 w-12 sm:h-9 sm:w-11"
        onPress={() => {
          setOpen(true)
        }}
      >
        <Icon as={Music} size={24} className={cn(!enabled && "opacity-40")} />
      </Button>
      <Modal
        visible={open}
        transparent
        animationType="slide"
        onRequestClose={() => {
          setOpen(false)
        }}
      >
        <View className="flex-1 justify-end">
          <Pressable
            accessibilityLabel="Close the music panel"
            className="flex-1"
            onPress={() => {
              setOpen(false)
            }}
          />
          <View
            className="bg-background border-border rounded-t-2xl border-t px-6"
            style={{ paddingBottom: insets.bottom + 16 }}
          >
            <View className="h-6 items-center justify-center">
              <View className="bg-muted-foreground/40 h-1 w-12 rounded-full" />
            </View>
            <LofiMusicControls music={music} />
          </View>
        </View>
      </Modal>
    </>
  )
}
