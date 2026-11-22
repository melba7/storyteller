// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useEffect, useState } from "react"
import { ScrollView, View } from "react-native"

import { Text } from "@/components/ui/text"
import {
  type AdResults as Results,
  type MacSection,
  macSection,
  resultsFor,
} from "@/modules/podcasts/adResults"
import {
  getAdResults,
  getTeachingState,
} from "@/modules/podcasts/adResultsNative"
import { Podcasts } from "@/modules/podcasts/index"
import { parseTeachingState } from "@/modules/podcasts/teaching"

import { BelowBar, ScreenBar } from "./ScreenBar"
import { ROW } from "./SettingsGroup"

/**
 * The "Ad skipping results" page: the totals (ads skipped, time saved, skips taken back, ads
 * marked as missed), a row for each show with the most missed and taken back first, and what
 * the Mac taught the phone.
 */
export function AdResults() {
  const [results, setResults] = useState<Results | null>(null)
  const [mac, setMac] = useState<MacSection>(() =>
    macSection(parseTeachingState(null), Date.now()),
  )

  useEffect(() => {
    let live = true
    getAdResults().then(
      (value) => {
        if (live) setResults(value)
      },
      () => {
        if (live) setResults(resultsFor({}, []))
      },
    )
    getTeachingState().then(
      (state) => {
        if (live) setMac(macSection(state, Date.now()))
      },
      () => {},
    )
    return () => {
      live = false
    }
  }, [])

  return (
    <>
      {Podcasts === null ? (
        <BelowBar>
          <Text className="text-muted-foreground px-8 py-12 text-center">
            Ad skipping results need the iOS app.
          </Text>
        </BelowBar>
      ) : (
        <ScrollView
          className="bg-background flex-1"
          contentContainerClassName="px-safe-or-4 pb-8"
          contentInsetAdjustmentBehavior="automatic"
        >
          {results === null ? null : results.empty ? (
            <View className="py-6">
              <Text className="text-xl font-semibold">No ads skipped yet</Text>
              <Text className="text-muted-foreground pt-1">
                When your phone skips an ad, it is counted here.
              </Text>
            </View>
          ) : (
            <>
              <View className="bg-secondary mt-4 rounded-3xl p-4">
                {results.totals.map((total) => (
                  <View
                    key={total.key}
                    className="flex-row items-center justify-between gap-3 py-1.5"
                  >
                    <Text className="flex-1">{total.label}</Text>
                    <Text className="text-lg font-bold tabular-nums">
                      {total.value}
                    </Text>
                  </View>
                ))}
              </View>
              <Text
                className="text-muted-foreground px-4 pt-6 pb-2 text-sm font-semibold"
                accessibilityRole="header"
              >
                Show by show
              </Text>
              <View className="bg-secondary rounded-3xl px-4">
                {results.rows.map((row, index) => (
                  <View
                    key={row.key}
                    className={`py-3 ${index < results.rows.length - 1 ? ROW : ""}`}
                  >
                    <Text>{row.text}</Text>
                  </View>
                ))}
              </View>
            </>
          )}
          <Text
            className="text-muted-foreground px-4 pt-6 pb-2 text-sm font-semibold"
            accessibilityRole="header"
          >
            What your Mac taught
          </Text>
          <View className="bg-secondary rounded-3xl p-4">
            {mac.empty ? (
              <>
                <Text className="font-semibold">{mac.empty.title}</Text>
                <Text className="text-muted-foreground pt-1 text-sm">
                  {mac.empty.text}
                </Text>
              </>
            ) : (
              mac.lines.map((line) => (
                <View key={line.key} className="py-1.5">
                  <Text className="font-semibold">{line.label}</Text>
                  <Text className="text-muted-foreground text-sm">
                    {line.text}
                  </Text>
                </View>
              ))
            )}
          </View>
        </ScrollView>
      )}
      <ScreenBar title="Ad skipping results" />
    </>
  )
}
