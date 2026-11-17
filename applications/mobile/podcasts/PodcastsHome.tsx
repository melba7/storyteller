// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import { StatusBar } from "expo-status-bar"
import { Ellipsis, Plus } from "lucide-react-native"
import { useMemo, useState } from "react"
import {
  ActivityIndicator,
  FlatList,
  RefreshControl,
  View,
  useWindowDimensions,
} from "react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Menu, type MenuAction } from "@/components/ui/menu"
import { Text } from "@/components/ui/text"
import { refreshAllShows } from "@/modules/podcasts/db"
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
import { showHref } from "@/modules/podcasts/routes"

import {
  GRID_GAP,
  GRID_GUTTER,
  ShowCell,
  ShowRow,
  cellSize,
} from "./LibraryShows"
import { ScreenBar } from "./ScreenBar"
import { SectionMenuButton } from "./SectionMenu"
import { useShowActivity, useShows } from "./hooks"
import { useLibraryView } from "./useLibraryView"

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

function menuActions(
  view: LibraryView,
  change: (patch: Partial<LibraryView>) => void,
  arrange: () => void,
  arranged: boolean,
): MenuAction[] {
  return [
    {
      id: "layout",
      title: "Layout",
      displayInline: true,
      subactions: LAYOUTS.map((layout) => ({
        id: `layout-${layout.id}`,
        title: layout.title,
        state: view.layout === layout.id ? "on" : "off",
        onPress: () => change({ layout: layout.id }),
      })),
    },
    {
      id: "order",
      title: "Sort by",
      displayInline: true,
      subactions: ORDERS.map((order) => ({
        id: `order-${order.id}`,
        title: order.title,
        state: view.order === order.id ? "on" : "off",
        // "Your order" opens the arrange screen until the listener has placed shows once.
        onPress: () =>
          order.id === "own" && !arranged
            ? arrange()
            : change({ order: order.id }),
      })),
    },
    {
      id: "arrange",
      title: "Arrange",
      displayInline: true,
      subactions: [
        { id: "arrange-shows", title: "Arrange shows", onPress: arrange },
      ],
    },
  ]
}

export function PodcastsHome() {
  const router = useRouter()
  const segments = useSegments()
  const { width } = useWindowDimensions()
  const shows = useShows()
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
      const { failed } = await refreshAllShows()
      if (failed.length > 0) {
        setRefreshProblem(`Couldn't refresh ${failed.join(", ")}.`)
      }
    } catch (cause) {
      setRefreshProblem(readableError(cause))
    } finally {
      setRefreshing(false)
    }
  }

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
    <View className="pt-safe bg-background flex-1">
      <StatusBar verticalBarBehaviorIOS="disabled" />
      <ScreenBar
        title="Podcasts"
        left={<SectionMenuButton current="podcasts" />}
        right={
          <View className="flex-row items-center">
            <Button
              variant="ghost"
              size="icon"
              accessibilityLabel="Find a podcast to add"
              onPress={() => router.navigate("/podcasts/discover")}
            >
              <Icon as={Plus} size={24} className="text-primary" />
            </Button>
            {view ? (
              <Menu actions={menuActions(view, change, openArrange, arranged)}>
                <Button
                  variant="ghost"
                  size="icon"
                  accessibilityLabel="Layout and order"
                >
                  <Icon as={Ellipsis} size={24} className="text-primary" />
                </Button>
              </Menu>
            ) : null}
          </View>
        }
      />
      {Podcasts === null ? (
        <Message
          title="Podcasts need the iOS app"
          body="This version of the app can't read podcast feeds."
        />
      ) : shows.loading || view === null ? (
        <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
      ) : shows.error ? (
        <Message title="The library couldn't be read" body={shows.error} />
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
            refreshProblem ? (
              <Text className="text-destructive py-2 text-sm">
                {refreshProblem}
              </Text>
            ) : undefined
          }
          ListEmptyComponent={
            <Message
              title="No podcasts yet"
              body="Tap the plus button to search for a show or paste its RSS link."
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
