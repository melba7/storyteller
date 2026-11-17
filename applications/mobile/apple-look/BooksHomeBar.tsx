// LOFI-FORK: the Apple Podcasts look for the Books side (see FORK.md).
import { Stack, useRouter } from "expo-router"
import { Image, TouchableOpacity } from "react-native"

import { SectionMenuButton } from "@/podcasts/SectionMenu"

import { LargeTitleBar } from "./LargeTitleBar"

interface Props {
  /** Picks an EPUB file and imports it, as the home menu's "Import book" did. */
  onImportBook: () => void
  /** Opens Settings. */
  onOpenSettings: () => void
  /** Scrolls the shelves back to the top, as the logo did in the home row. */
  onScrollToTop: () => void
}

/**
 * The Books home screen's native bar on iOS: the large title "Books", the side menu with
 * Books and Podcasts and the logo (which scrolls to the top) at the left, and Search and the
 * home menu (Import book, Settings) as round buttons at the right. Android keeps the home
 * screen's own row of controls.
 */
export function BooksHomeBar({
  onImportBook,
  onOpenSettings,
  onScrollToTop,
}: Props) {
  const router = useRouter()
  return (
    <LargeTitleBar
      large
      title="Books"
      left={
        <>
          <Stack.Toolbar.View>
            <SectionMenuButton current="books" />
          </Stack.Toolbar.View>
          <Stack.Toolbar.View>
            <TouchableOpacity
              accessibilityLabel="Scroll to top"
              accessibilityRole="button"
              className="h-9 w-9 items-center justify-center"
              onPress={onScrollToTop}
            >
              <Image
                // eslint-disable-next-line @typescript-eslint/no-require-imports
                source={require("../assets/Storyteller_Logo.png")}
                className="h-8 w-8"
              />
            </TouchableOpacity>
          </Stack.Toolbar.View>
        </>
      }
      right={
        <>
          <Stack.Toolbar.Button
            icon="magnifyingglass"
            accessibilityLabel="Search books"
            onPress={() => router.push("/search")}
          />
          <Stack.Toolbar.Menu
            icon="ellipsis"
            accessibilityLabel="Open home menu"
          >
            <Stack.Toolbar.MenuAction
              icon="square.and.arrow.down"
              onPress={onImportBook}
            >
              Import book
            </Stack.Toolbar.MenuAction>
            <Stack.Toolbar.MenuAction icon="gearshape" onPress={onOpenSettings}>
              Settings
            </Stack.Toolbar.MenuAction>
          </Stack.Toolbar.Menu>
        </>
      }
    />
  )
}
