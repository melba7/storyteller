import { skipToken } from "@reduxjs/toolkit/query"
import deepmerge from "deepmerge"
import { Columns2, ScrollText } from "lucide-react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { useAppSelector } from "@/store/appState"
import {
  useGetBookPreferencesQuery,
  useGetGlobalPreferencesQuery,
  useUpdateBookPreferenceMutation,
} from "@/store/localApi"
import { getCurrentlyPlayingBookUuid } from "@/store/selectors/bookshelfSelectors"

type Props = {
  /** Colour class for the icon. */
  iconClassName?: string
}

export function LayoutItem({ iconClassName = "text-foreground" }: Props) {
  const bookUuid = useAppSelector(getCurrentlyPlayingBookUuid)
  const { data: bookPreferences } = useGetBookPreferencesQuery(
    bookUuid ? { uuid: bookUuid } : skipToken,
  )
  const { data: globalPreferences } = useGetGlobalPreferencesQuery()
  const [updateBookPreference] = useUpdateBookPreferenceMutation()

  const preferences = bookPreferences
    ? globalPreferences && deepmerge(globalPreferences, bookPreferences)
    : globalPreferences

  const isScrollLayout = preferences?.layout.scroll ?? false
  const nextLayout = isScrollLayout ? "page" : "scroll"

  return (
    <Button
      accessibilityLabel={
        isScrollLayout
          ? "Reader layout: scroll. Switch to page layout"
          : "Reader layout: page. Switch to scroll layout"
      }
      accessibilityState={{ selected: isScrollLayout }}
      variant="ghost"
      size="icon"
      className="h-10 w-10 rounded-full sm:h-10 sm:w-10"
      disabled={!bookUuid || !preferences}
      onPress={() => {
        if (!bookUuid || !preferences) return

        const value = {
          ...preferences.layout,
          scroll: nextLayout === "scroll",
        }

        updateBookPreference({ bookUuid, name: "layout", value })
      }}
    >
      <Icon
        as={isScrollLayout ? ScrollText : Columns2}
        size={24}
        className={iconClassName}
      />
    </Button>
  )
}
