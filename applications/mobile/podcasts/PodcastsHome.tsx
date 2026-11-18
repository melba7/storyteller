// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack, useRouter, useSegments } from "expo-router"
import { StatusBar } from "expo-status-bar"
import { Podcast } from "lucide-react-native"
import { useMemo } from "react"
import {
  ActivityIndicator,
  FlatList,
  RefreshControl,
  View,
  useWindowDimensions,
} from "react-native"

import { Text } from "@/components/ui/text"
import { Podcasts } from "@/modules/podcasts/index"
import { type Show } from "@/modules/podcasts/library"
import {
  type LibraryLayout,
  type LibraryOrder,
  type LibraryView,
  badgeCount,
  sortShows,
} from "@/modules/podcasts/libraryView"
import { SEARCH_HREF, arrangeHref, showHref } from "@/modules/podcasts/routes"

import { EmptyState } from "./EmptyState"
import {
  GRID_GAP,
  GRID_GUTTER,
  ShowCell,
  ShowRow,
  cellSize,
} from "./LibraryShows"
import { BelowBar, ScreenBar } from "./ScreenBar"
import { addAudioFiles } from "./addAudioFiles"
import { useShowActivity, useShows } from "./hooks"
import { useLibraryView } from "./useLibraryView"
import { useStatusBarStyle } from "./usePodcastsTheme"
import { useRefreshShows } from "./useRefreshShows"

const LAYOUTS: { id: LibraryLayout; title: string; columns: number }[] = [
  { id: "large", title: "Large grid", columns: 3 },
  { id: "small", title: "Small grid", columns: 4 },
  { id: "list", title: "List", columns: 1 },
]

const ORDERS: { id: LibraryOrder; title: string }[] = [
  { id: "name", title: "Name" },
  { id: "added", title: "Date added" },
  { id: "newest", title: "Newest episode" },
  { id: "own", title: "Your order" },
]

/** The "…" menu's native items: Layout, Sort by, Add audio files and Arrange. */
function menuItems(
  view: LibraryView,
  change: (patch: Partial<LibraryView>) => void,
  arrange: () => void,
  arranged: boolean,
) {
  return [
    <Stack.Toolbar.Menu key="layout" inline title="Layout">
      {LAYOUTS.map((layout) => (
        <Stack.Toolbar.MenuAction
          key={layout.id}
          isOn={view.layout === layout.id}
          onPress={() => change({ layout: layout.id })}
        >
          {layout.title}
        </Stack.Toolbar.MenuAction>
      ))}
    </Stack.Toolbar.Menu>,
    <Stack.Toolbar.Menu key="order" inline title="Sort by">
      {ORDERS.map((order) => (
        <Stack.Toolbar.MenuAction
          key={order.id}
          isOn={view.order === order.id}
          // "Your order" opens the arrange screen until the listener has placed shows once.
          onPress={() =>
            order.id === "own" && !arranged
              ? arrange()
              : change({ order: order.id })
          }
        >
          {order.title}
        </Stack.Toolbar.MenuAction>
      ))}
    </Stack.Toolbar.Menu>,
    <Stack.Toolbar.MenuAction
      key="add-files"
      icon="doc.badge.plus"
      onPress={() => void addAudioFiles()}
    >
      Add audio files
    </Stack.Toolbar.MenuAction>,
    <Stack.Toolbar.Menu key="arrange" inline title="Arrange">
      <Stack.Toolbar.MenuAction onPress={arrange}>
        Arrange shows
      </Stack.Toolbar.MenuAction>
    </Stack.Toolbar.Menu>,
  ]
}

export function PodcastsHome() {
  const statusBarStyle = useStatusBarStyle()
  const router = useRouter()
  const segments = useSegments()
  const { width } = useWindowDimensions()
  const shows = useShows()
  const activity = useShowActivity()
  const { view, change } = useLibraryView()
  const { refreshing, problem: refreshProblem, refresh } = useRefreshShows()

  // If the activity query fails, no badges show and the newest-episode order falls back to name.
  const found = activity.data
  const sorted = useMemo(
    () => (view ? sortShows(shows.data ?? [], view.order, found ?? {}) : []),
    [shows.data, view, found],
  )

  const arranged = (shows.data ?? []).some((s) => s.ownPosition !== null)
  const openArrange = () => router.push(arrangeHref(segments))
  const columns = LAYOUTS.find((l) => l.id === view?.layout)?.columns ?? 3
  const size = cellSize(width, columns)
  const isList = view?.layout === "list"

  function renderShow({ item }: { item: Show }) {
    const props = {
      show: item,
      count: badgeCount(found?.[item.id], item.addedAt),
      onPress: () => router.push(showHref(segments, item.id)),
    }
    return isList ? (
      <ShowRow {...props} />
    ) : (
      <ShowCell {...props} size={size} href={showHref(segments, item.id)} />
    )
  }

  return (
    <>
      {Podcasts === null ? (
        <BelowBar>
          <Message
            title="Podcasts need the iOS app"
            body="This version of the app can't read podcast feeds."
          />
        </BelowBar>
      ) : shows.loading || view === null ? (
        <BelowBar>
          <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
        </BelowBar>
      ) : shows.error ? (
        <BelowBar>
          <Message title="The library couldn't be read" body={shows.error} />
        </BelowBar>
      ) : (
        <FlatList<Show>
          // A different column count needs a fresh list.
          key={`columns-${columns}`}
          className="bg-background flex-1"
          data={sorted}
          numColumns={columns}
          keyExtractor={(show) => show.id}
          contentInsetAdjustmentBehavior="automatic"
          contentContainerStyle={
            isList
              ? { paddingHorizontal: GRID_GUTTER, flexGrow: 1 }
              : { paddingHorizontal: GRID_GUTTER, paddingTop: 4, flexGrow: 1 }
          }
          columnWrapperStyle={isList ? undefined : { gap: GRID_GAP }}
          refreshControl={
            <RefreshControl refreshing={refreshing} onRefresh={refresh} />
          }
          ListHeaderComponent={
            <>
              {refreshProblem ? (
                <View className="bg-destructive/10 mb-3 rounded-xl p-3">
                  <Text
                    className="text-destructive text-sm"
                    accessibilityRole="alert"
                  >
                    {refreshProblem}
                  </Text>
                </View>
              ) : null}
            </>
          }
          ListEmptyComponent={
            <EmptyState
              icon={Podcast}
              title="No podcasts yet"
              body="Search for a show, or paste its RSS or Apple Podcasts link."
              action={{
                label: "Find a podcast",
                onPress: () => router.navigate(SEARCH_HREF),
              }}
            />
          }
          renderItem={renderShow}
        />
      )}
      <StatusBar style={statusBarStyle} verticalBarBehaviorIOS="disabled" />
      <ScreenBar
        large
        title="Shows"
        right={
          <>
            <Stack.Toolbar.Button
              icon="plus"
              accessibilityLabel="Find a podcast to add"
              onPress={() => router.navigate(SEARCH_HREF)}
            />
            <Stack.Toolbar.Menu
              icon="ellipsis"
              hidden={!view}
              accessibilityLabel="Layout and order"
            >
              {view ? menuItems(view, change, openArrange, arranged) : null}
            </Stack.Toolbar.Menu>
          </>
        }
      />
    </>
  )
}

function Message({ title, body }: { title: string; body: string }) {
  return (
    <View className="items-center gap-2 px-8 py-12">
      <Text className="text-center font-semibold">{title}</Text>
      <Text className="text-muted-foreground text-center text-sm">{body}</Text>
    </View>
  )
}
