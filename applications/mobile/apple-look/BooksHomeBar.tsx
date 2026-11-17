// LOFI-FORK: the Apple Podcasts look for the Books side (see FORK.md).
import { Stack, useRouter } from "expo-router"

import { SectionMenuButton } from "@/podcasts/SectionMenu"

import { LargeTitleBar } from "./LargeTitleBar"

interface Props {
  /** Picks an EPUB file and imports it, as the home menu's "Import book" did. */
  onImportBook: () => void
  /** Opens Settings. */
  onOpenSettings: () => void
}

/**
 * The Books home screen's native bar on iOS: the large title "Books", the side menu with
 * Books and Podcasts at the left, and Search and the home menu (Import book, Settings) as
 * round buttons at the right. Android keeps the home screen's own row of controls.
 */
export function BooksHomeBar({ onImportBook, onOpenSettings }: Props) {
  const router = useRouter()
  return (
    <LargeTitleBar
      large
      title="Books"
      left={
        <Stack.Toolbar.View>
          <SectionMenuButton current="books" />
        </Stack.Toolbar.View>
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
