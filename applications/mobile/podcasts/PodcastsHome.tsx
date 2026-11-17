// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack, useRouter, useSegments } from "expo-router"
import { StatusBar } from "expo-status-bar"
import { Download, Podcast } from "lucide-react-native"
import { useMemo, useState } from "react"
import {
  ActivityIndicator,
  FlatList,
  RefreshControl,
  View,
  useWindowDimensions,
} from "react-native"

import { Text } from "@/components/ui/text"
import { followUpNew } from "@/modules/podcasts/automaticRun"
import { downloadsSummary } from "@/modules/podcasts/downloads"
import { refreshAllShows } from "@/modules/podcasts/dbFeeds"
import { Podcasts } from "@/modules/podcasts/index"
import { type Show } from "@/modules/podcasts/library"
import {
  type LibraryLayout,
  type LibraryOrder,
  type LibraryView,
  badgeCount,
  sortShows,
} from "@/modules/podcasts/libraryView"
import { readableError } from "@/modules/podcasts/nativeError"
import { downloadsHref, showHref } from "@/modules/podcasts/routes"

import { EmptyState } from "./EmptyState"
import {
  GRID_GAP,
  GRID_GUTTER,
  ShowCell,
  ShowRow,
  cellSize,
} from "./LibraryShows"
import { BelowBar, ScreenBar } from "./ScreenBar"
import { SectionMenuButton } from "./SectionMenu"
import { LinkRow } from "./SettingsGroup"
import { addAudioFiles } from "./addAudioFiles"
import { useShowActivity, useShows } from "./hooks"
import { useDownloadMap } from "./useDownloads"
import { useLibraryView } from "./useLibraryView"
import { useStatusBarStyle } from "./usePodcastsTheme"

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
  const downloads = useDownloadMap()
  const activity = useShowActivity()
  const { view, change } = useLibraryView()
  const [refreshing, setRefreshing] = useState(false)
  const [refreshProblem, setRefreshProblem] = useState<string | null>(null)

  // If the activity query fails, no badges show and the newest-episode order falls back to name.
  const found = activity.data
  const sorted = useMemo(
    () => (view ? sortShows(shows.data ?? [], view.order, found ?? {}) : []),
    [shows.data, view, found],
  )

  async function refresh() {
    setRefreshing(true)
    setRefreshProblem(null)
    try {
      const { failed, added } = await refreshAllShows()
      await followUpNew(added)
      if (failed.length > 0) {
        setRefreshProblem(`Couldn't refresh ${failed.join(", ")}.`)
      }
    } catch (cause) {
      setRefreshProblem(readableError(cause))
    } finally {
      setRefreshing(false)
    }
  }

  const summary = downloadsSummary(downloads)
  const arranged = (shows.data ?? []).some((s) => s.ownPosition !== null)
  const openArrange = () => router.push("/podcasts/arrange")
  const columns = LAYOUTS.find((l) => l.id === view?.layout)?.columns ?? 3
  const size = cellSize(width, columns)
  const isList = view?.layout === "list"

  function renderShow({ item }: { item: Show }) {
    const props = {
      show: item,
      count: badgeCount(found?.[item.id], item.addedAt),
      onPress: () => router.push(showHref(segments, item.id)),
    }
    return isList ? <ShowRow {...props} /> : <ShowCell {...props} size={size} />
  }

  return (
    <View className="bg-background flex-1">
      <StatusBar style={statusBarStyle} verticalBarBehaviorIOS="disabled" />
      <ScreenBar
        large
        title="Podcasts"
        left={
          <Stack.Toolbar.View>
            <SectionMenuButton current="podcasts" />
          </Stack.Toolbar.View>
        }
        right={
          <>
            <Stack.Toolbar.Button
              icon="magnifyingglass"
              accessibilityLabel="Search episodes"
              onPress={() => router.push("/podcasts/search")}
            />
            <Stack.Toolbar.Button
              icon="plus"
              accessibilityLabel="Find a podcast to add"
              onPress={() => router.navigate("/podcasts/discover")}
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
              <View className="bg-secondary mb-3 overflow-hidden rounded-3xl px-4">
                <LinkRow
                  icon={Download}
                  title="Downloaded"
                  body={summary}
                  label={`Downloaded, ${summary}`}
                  onPress={() => router.push(downloadsHref(segments))}
                />
              </View>
            </>
          }
          ListEmptyComponent={
            <EmptyState
              icon={Podcast}
              title="No podcasts yet"
              body="Search for a show, or paste its RSS or Apple Podcasts link."
              action={{
                label: "Find a podcast",
                onPress: () => router.navigate("/podcasts/discover"),
              }}
            />
          }
          renderItem={renderShow}
        />
      )}
    </View>
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
