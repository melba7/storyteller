// LOFI-FORK: the atmosphere button in the player's toolbar, and the panel it
// opens (see FORK.md).
import AsyncStorage from "@react-native-async-storage/async-storage"
import { AudioLines } from "lucide-react-native"
import { useEffect, useState } from "react"
import { Modal, Pressable, View } from "react-native"
import { useSafeAreaInsets } from "react-native-safe-area-context"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { cn } from "@/lib/utils"
import { logger } from "@/logger"
import { restoreLeftoverPlace } from "@/modules/lofi-score/soundCheckRunner"
import { Storyteller } from "@/modules/readium"
import { useAppSelector } from "@/store/appState"
import { getCurrentlyPlayingBookUuid } from "@/store/selectors/bookshelfSelectors"

import { LofiAtmosphereControls } from "./LofiAtmosphereControls"
import { LofiSoundCheck } from "./LofiSoundCheck"
import { readerHidden, readerShown } from "./readerFollow"
import { useBookScore } from "./useBookScore"
import { useLofiAtmosphere } from "./useLofiAtmosphere"

type Props = {
  /** The toolbar's screen: the reader ("text") or the listening screen. */
  mode: "audio" | "text"
  /** Colour class for the icon. */
  iconClassName?: string
}

/**
 * Opens the atmosphere panel: on and off, the sounds' volume under the voice,
 * how much is going on, and the car setting. Shown for readaloud books, where
 * there is text to follow.
 */
export function LofiAtmosphereToolbarItem({
  mode,
  iconClassName = "text-foreground",
}: Props) {
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

  // A sound check the app closed in the middle of left the narration at one
  // of its stops. Put it back as soon as the book is on screen, before the
  // listener plays on from the wrong place.
  useEffect(() => {
    if (!bookUuid) return
    restoreLeftoverPlace(Storyteller, AsyncStorage, bookUuid).catch(
      (error: unknown) => {
        logger.error(`Lofi sound check, restoring: ${String(error)}`)
      },
    )
  }, [bookUuid])

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
        className="h-11 w-11 rounded-full sm:h-11 sm:w-11"
        onPress={() => {
          setOpen(true)
        }}
      >
        <Icon
          as={AudioLines}
          size={24}
          className={cn(iconClassName, !enabled && "opacity-40")}
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
            className="bg-secondary dark:bg-background border-border rounded-t-[26px] border-t px-4"
            style={{ paddingBottom: insets.bottom + 16 }}
          >
            <View className="h-6 items-center justify-center">
              <View className="bg-muted-foreground/40 h-1 w-12 rounded-full" />
            </View>
            <View>
              <LofiAtmosphereControls atmosphere={atmosphere} />
              <LofiSoundCheck atmosphere={atmosphere} />
            </View>
          </View>
        </View>
      </Modal>
    </>
  )
}
