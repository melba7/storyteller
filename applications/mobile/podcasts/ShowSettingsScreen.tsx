// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Minus, Plus } from "lucide-react-native"
import { type ReactNode } from "react"
import { ActivityIndicator, ScrollView, View } from "react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Menu } from "@/components/ui/menu"
import { Switch } from "@/components/ui/switch"
import { Text } from "@/components/ui/text"
import { saveShowSettings } from "@/modules/podcasts/dbSettings"
import { speedLabel } from "@/modules/podcasts/playbackRules"
import {
  type AfterPlayed,
  type AutoUpNext,
  KEEP_NEWEST,
  SKIP_MAX,
  type ShowSettings,
  UNPLAYED_DAYS,
  afterDaysLabel,
  afterPlayedLabel,
  followLabel,
  keepNewestLabel,
  skipLabel,
  stepSkip,
  upNextLabel,
} from "@/modules/podcasts/showSettings"

import { ScreenBar } from "./ScreenBar"
import { useShow } from "./hooks"

const SPEEDS = [0.8, 1, 1.2, 1.5, 1.7, 2, 2.5, 3]

function Row({
  title,
  body,
  children,
}: {
  title: string
  body?: string
  children: ReactNode
}) {
  return (
    <View className="border-border flex-row items-center gap-3 border-b py-3">
      <View className="flex-1">
        <Text className="font-semibold">{title}</Text>
        {body ? (
          <Text className="text-muted-foreground text-sm">{body}</Text>
        ) : null}
      </View>
      {children}
    </View>
  )
}

function Heading({ children }: { children: string }) {
  return (
    <Text className="text-muted-foreground px-1 pt-6 pb-1 text-xs uppercase">
      {children}
    </Text>
  )
}

function SwitchRow(props: {
  title: string
  body?: string
  checked: boolean
  onChange: (on: boolean) => void
}) {
  return (
    <Row title={props.title} {...(props.body ? { body: props.body } : {})}>
      <Switch
        accessibilityLabel={props.title}
        checked={props.checked}
        onCheckedChange={props.onChange}
      />
    </Row>
  )
}

/** A row whose value is picked from a menu. */
function ChoiceRow<T extends string | number | boolean | null>({
  title,
  body,
  value,
  options,
  label,
  onChange,
}: {
  title: string
  body?: string
  value: T
  options: readonly T[]
  label: (value: T) => string
  onChange: (value: T) => void
}) {
  return (
    <Row title={title} {...(body ? { body } : {})}>
      <Menu
        actions={options.map((option) => ({
          id: String(option),
          title: label(option),
          state: option === value ? "on" : "off",
          onPress: () => onChange(option),
        }))}
      >
        <Button
          variant="outline"
          size="sm"
          accessibilityLabel={`${title}: ${label(value)}`}
        >
          <Text>{label(value)}</Text>
        </Button>
      </Menu>
    </Row>
  )
}

function SkipRow({
  title,
  seconds,
  onChange,
}: {
  title: string
  seconds: number
  onChange: (seconds: number) => void
}) {
  return (
    <Row title={title}>
      <Button
        variant="outline"
        size="icon"
        accessibilityLabel={`Less ${title}`}
        disabled={seconds <= 0}
        onPress={() => onChange(stepSkip(seconds, -1))}
      >
        <Icon as={Minus} size={18} className="text-foreground" />
      </Button>
      <Text className="w-28 text-center">{skipLabel(seconds)}</Text>
      <Button
        variant="outline"
        size="icon"
        accessibilityLabel={`More ${title}`}
        disabled={seconds >= SKIP_MAX}
        onPress={() => onChange(stepSkip(seconds, 1))}
      >
        <Icon as={Plus} size={18} className="text-foreground" />
      </Button>
    </Row>
  )
}

const FOLLOW = [null, true, false] as const
const AFTER_PLAYED: readonly AfterPlayed[] = ["never", "now", "day", "week"]
const UP_NEXT: readonly AutoUpNext[] = ["off", "top", "bottom"]
const DAYS: readonly (number | null)[] = [null, ...UNPLAYED_DAYS]
const KEEP: readonly (number | null)[] = [null, ...KEEP_NEWEST]
const SPEED_CHOICES: readonly (number | null)[] = [null, ...SPEEDS]

/** One show's own settings: playback, new episodes, ads and archiving. */
export function ShowSettingsScreen({ id }: { id: string }) {
  const show = useShow(id)
  const current = show.data
  if (show.loading) {
    return (
      <View className="pt-safe bg-background flex-1">
        <ScreenBar title="Show settings" />
        <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
      </View>
    )
  }
  if (!current) {
    return (
      <View className="pt-safe bg-background flex-1">
        <ScreenBar title="Show settings" />
        <Text className="text-muted-foreground px-8 py-12 text-center">
          {show.error ?? "This show isn't in your library."}
        </Text>
      </View>
    )
  }
  const settings = current.settings
  const change = (patch: Partial<ShowSettings>) => {
    saveShowSettings(id, { ...settings, ...patch }).catch((cause: unknown) =>
      console.warn("Couldn't save the show's settings", cause),
    )
  }
  return (
    <View className="pt-safe bg-background flex-1">
      <ScreenBar title={current.title} />
      <ScrollView
        contentContainerClassName="px-safe-or-4 pb-12"
        contentInsetAdjustmentBehavior="automatic"
      >
        <Heading>Playback</Heading>
        <SkipRow
          title="Skip intro"
          seconds={settings.skipIntro}
          onChange={(skipIntro) => change({ skipIntro })}
        />
        <SkipRow
          title="Skip outro"
          seconds={settings.skipOutro}
          onChange={(skipOutro) => change({ skipOutro })}
        />
        <ChoiceRow
          title="Speed"
          body="This show's own speed, or the player's."
          value={settings.speed}
          options={SPEED_CHOICES}
          label={(v) => (v === null ? "Follow the player" : speedLabel(v))}
          onChange={(speed) => change({ speed })}
        />
        <Heading>New episodes</Heading>
        <SwitchRow
          title="Download new episodes"
          body="Only when the main setting in Profile is on too."
          checked={settings.autoDownload}
          onChange={(autoDownload) => change({ autoDownload })}
        />
        <ChoiceRow
          title="Add to Up Next"
          value={settings.autoUpNext}
          options={UP_NEXT}
          label={upNextLabel}
          onChange={(autoUpNext) => change({ autoUpNext })}
        />
        <SwitchRow
          title="Notify about new episodes"
          checked={settings.notify}
          onChange={(notify) => change({ notify })}
        />
        <Heading>Ads</Heading>
        <ChoiceRow
          title="Skip ads"
          value={settings.skipAds}
          options={FOLLOW}
          label={followLabel}
          onChange={(skipAds) => change({ skipAds })}
        />
        <ChoiceRow
          title="Skip the hosts' own plugs"
          value={settings.skipPlugs}
          options={FOLLOW}
          label={followLabel}
          onChange={(skipPlugs) => change({ skipPlugs })}
        />
        <Heading>Archive</Heading>
        <ChoiceRow
          title="After playing"
          body="Archiving removes the download. The episode being played or in Up Next stays."
          value={settings.archiveAfterPlayed}
          options={AFTER_PLAYED}
          label={afterPlayedLabel}
          onChange={(archiveAfterPlayed) => change({ archiveAfterPlayed })}
        />
        <ChoiceRow
          title="After days unplayed"
          value={settings.archiveAfterDays}
          options={DAYS}
          label={afterDaysLabel}
          onChange={(archiveAfterDays) => change({ archiveAfterDays })}
        />
        <ChoiceRow
          title="Keep only"
          value={settings.keepNewest}
          options={KEEP}
          label={keepNewestLabel}
          onChange={(keepNewest) => change({ keepNewest })}
        />
      </ScrollView>
    </View>
  )
}
