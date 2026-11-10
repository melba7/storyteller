// LOFI-FORK: the atmosphere button in the player's toolbar, and the panel it
// opens (see FORK.md).
import { AudioLines } from "lucide-react-native"
import { useEffect, useState } from "react"
import { Modal, Pressable, View } from "react-native"
import { useSafeAreaInsets } from "react-native-safe-area-context"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { cn } from "@/lib/utils"
import { useAppSelector } from "@/store/appState"
import { getCurrentlyPlayingBookUuid } from "@/store/selectors/bookshelfSelectors"

import { LofiAtmosphereControls } from "./LofiAtmosphereControls"
import { readerHidden, readerShown } from "./readerFollow"
import { useBookScore } from "./useBookScore"
import { useLofiAtmosphere } from "./useLofiAtmosphere"

type Props = {
  /** The toolbar's screen: the reader ("text") or the listening screen. */
  mode: "audio" | "text"
}

/**
 * Opens the atmosphere panel: on and off, the sounds' volume under the voice,
 * how much is going on, and the car setting. Shown for readaloud books, where
 * there is text to follow.
 */
export function LofiAtmosphereToolbarItem({ mode }: Props) {
  const [open, setOpen] = useState(false)
  const atmosphere = useLofiAtmosphere(open ? 1500 : 15000)
  const insets = useSafeAreaInsets()

  const bookUuid = useAppSelector(getCurrentlyPlayingBookUuid)

  // A book without a score asks the server for one (the Mac puts each score
  // inside the book on the server), so it arrives with the book.
  useBookScore(atmosphere.status, atmosphere.refresh)

  // The reader's toolbar comes and goes with the reader. The sounds that
  // follow the pages wait for the first page turn after the book opens, and
  // stop when the book closes.
  useEffect(() => {
    if (mode !== "text" || !bookUuid) return
    readerShown(bookUuid)
    return () => {
      readerHidden()
    }
  }, [mode, bookUuid])

  if (!atmosphere.available) return null
  const enabled = atmosphere.status?.atmosphere.enabled ?? true

  return (
    <>
      <Button
        accessibilityLabel={
          enabled
            ? "Atmosphere sounds are on. Adjust them"
            : "Atmosphere sounds are off. Adjust them"
        }
        variant="ghost"
        size="icon"
        className="h-10 w-12 sm:h-9 sm:w-11"
        onPress={() => {
          setOpen(true)
        }}
      >
        <Icon
          as={AudioLines}
          size={24}
          className={cn(!enabled && "opacity-40")}
        />
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
            accessibilityLabel="Close the atmosphere panel"
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
            <LofiAtmosphereControls atmosphere={atmosphere} />
          </View>
        </View>
      </Modal>
    </>
  )
}
