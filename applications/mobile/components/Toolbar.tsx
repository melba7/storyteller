import { skipToken } from "@reduxjs/toolkit/query"
import { Link } from "expo-router"
import { BookOpen, Headphones } from "lucide-react-native"
import { View } from "react-native"

import { GlassCapsule } from "@/apple-look/GlassCapsule"
import { type Bookmark } from "@/database/bookmarks"
import { cn } from "@/lib/utils"
import { LofiAtmosphereToolbarItem } from "@/lofi/LofiAtmosphereToolbarItem" // LOFI-FORK
import { useAppSelector } from "@/store/appState"
import { useGetBookQuery } from "@/store/localApi"
import {
  getCurrentlyPlayingBookUuid,
  getCurrentlyPlayingFormat,
} from "@/store/selectors/bookshelfSelectors"

import { BookmarkItem } from "./toolbarItems/BookmarkItem"
import { LayoutItem } from "./toolbarItems/LayoutItem"
import { NavigationItem } from "./toolbarItems/NavigationItem"
import { SettingsItem } from "./toolbarItems/SettingsItem"
import { SleepTimerItem } from "./toolbarItems/SleepTimerItem"
import { SpeedItem } from "./toolbarItems/SpeedItem"
import { Button } from "./ui/button"
import { Icon } from "./ui/icon"

type Props = {
  mode: "audio" | "text"
  activeBookmarks: Bookmark[]
  /**
   * Stack the items for the vertical rail instead of laying them out in a bar.
   */
  vertical?: boolean
  /**
   * The screen behind the toolbar is washed with the cover's colour, so the
   * icons are white.
   */
  onWash?: boolean
}

export function Toolbar({
  mode,
  activeBookmarks,
  vertical = false,
  onWash = false,
}: Props) {
  const bookUuid = useAppSelector(getCurrentlyPlayingBookUuid)
  const selectedFormat = useAppSelector(getCurrentlyPlayingFormat)
  const format = selectedFormat ?? "readaloud"

  const { data: book } = useGetBookQuery(
    bookUuid ? { uuid: bookUuid } : skipToken,
  )
  if (!book) return null

  // Purple in the reader, and the label colour (or white over the wash) in the player.
  const tone =
    mode === "text"
      ? "text-primary"
      : onWash
        ? "text-white"
        : "text-foreground"

  const items = (
    <>
      <View
        className={cn("items-center gap-1", vertical ? "flex-col" : "flex-row")}
      >
        {mode === "text" && <LayoutItem iconClassName={tone} />}
        {mode === "text" && <SettingsItem iconClassName={tone} />}
        {mode === "audio" && <SleepTimerItem iconClassName={tone} />}
        {mode === "text" &&
          (vertical ? (
            <SleepTimerItem iconClassName={tone} />
          ) : (
            // In a bar there is not always room for the sleep timer as well.
            <View className="xs:flex hidden">
              <SleepTimerItem iconClassName={tone} />
            </View>
          ))}
        <SpeedItem iconClassName={tone} />
        {/* LOFI-FORK: atmosphere sounds for readaloud books, see FORK.md */}
        {format === "readaloud" && (
          <LofiAtmosphereToolbarItem mode={mode} iconClassName={tone} />
        )}
        <NavigationItem mode={mode} iconClassName={tone} />
        <BookmarkItem activeBookmarks={activeBookmarks} iconClassName={tone} />
        {format === "readaloud" &&
          (mode === "audio" ? (
            <Link
              asChild
              replace
              href={{
                pathname: "/read/[uuid]",
                params: { uuid: book.uuid, format },
              }}
            >
              <Button
                accessibilityLabel={`Switch to reading ${book.title}`}
                variant="ghost"
                size="icon"
                className="h-11 w-11 rounded-full sm:h-11 sm:w-11"
              >
                <Icon as={BookOpen} size={24} className={tone} />
              </Button>
            </Link>
          ) : (
            <Link
              asChild
              replace
              href={{
                pathname: "/listen/[uuid]",
                params: { uuid: book.uuid, format },
              }}
            >
              <Button
                accessibilityLabel={`Switch to listening to ${book.title}`}
                variant="ghost"
                size="icon"
                className="h-11 w-11 rounded-full sm:h-11 sm:w-11"
              >
                <Icon as={Headphones} size={24} className={tone} />
              </Button>
            </Link>
          ))}
      </View>
    </>
  )

  // In the reader the bar floats on a glass capsule; in the player it sits
  // straight on the cover's wash.
  if (mode === "audio") return items

  return (
    <GlassCapsule className={vertical ? "py-1" : "px-1"}>{items}</GlassCapsule>
  )
}
