import Constants from "expo-constants"
import { Link, Stack } from "expo-router"
import {
  BookOpenIcon,
  BugIcon,
  ExternalLinkIcon,
  PlusIcon,
} from "lucide-react-native"
import { View } from "react-native"
import { ScrollView } from "react-native-gesture-handler"

import {
  GroupedRow,
  GroupedSection,
  groupedScreenClass,
} from "@/apple-look/GroupedList"
import { LoadingView } from "@/components/LoadingView"
import { LoginButton } from "@/components/LoginButton"
import { MiniPlayerWidget } from "@/components/MiniPlayerWidget"
import { ReadingSettings } from "@/components/ReadingSettings"
import { ScreenBackButton } from "@/components/ScreenBackButton"
import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Slider } from "@/components/ui/slider"
import { Switch } from "@/components/ui/switch"
import { Text } from "@/components/ui/text"
import { DiscordIcon } from "@/icons/DiscordIcon"
import { usesSystemHeader } from "@/lib/nativeChrome"
import { cn } from "@/lib/utils"
import { LofiAtmosphereSettings } from "@/lofi/LofiAtmosphereSettings" // LOFI-FORK
import {
  useDeleteServerMutation,
  useGetGlobalPreferencesQuery,
  useListServersQuery,
  useUpdateGlobalPreferenceMutation,
} from "@/store/localApi"

export default function Settings() {
  const { data: servers } = useListServersQuery()
  const [deleteServer] = useDeleteServerMutation()
  const [updatePreference] = useUpdateGlobalPreferenceMutation()
  const { data: preferences } = useGetGlobalPreferencesQuery()

  if (!preferences) return <LoadingView />

  const externalIcon = (
    <Icon as={ExternalLinkIcon} size={14} className="text-muted-foreground" />
  )

  return (
    <>
      <ScrollView
        className={cn("flex-1", groupedScreenClass)}
        contentContainerClassName="px-safe-or-4 pb-40"
        contentInsetAdjustmentBehavior={
          usesSystemHeader ? "automatic" : "never"
        }
      >
        <GroupedSection title="Servers">
          {servers?.flatMap((server) => {
            const serverUrl = new URL(server.baseUrl)
            const homepageUrl = new URL("/", serverUrl.origin)

            return [
              <GroupedRow
                key={`${server.uuid}-host`}
                title={server.username ? "Logged in to" : "Logging in to"}
                trailing={
                  <View className="max-w-[60%] shrink">
                    <Link href={homepageUrl.toString()} numberOfLines={1}>
                      <Text className="text-link text-[17px]">
                        {serverUrl.hostname}
                      </Text>
                    </Link>
                  </View>
                }
              />,
              server.username ? (
                <GroupedRow
                  key={`${server.uuid}-user`}
                  title="Logged in as"
                  value={server.username}
                />
              ) : null,
              <GroupedRow key={`${server.uuid}-action`} className="py-2">
                {server.username ? (
                  <Button
                    accessibilityLabel={`Log out of ${serverUrl.hostname}`}
                    variant="secondary"
                    size="flex"
                    onPress={() => {
                      deleteServer({ uuid: server.uuid })
                    }}
                  >
                    <Text>Log out</Text>
                  </Button>
                ) : (
                  <LoginButton
                    serverUrl={homepageUrl.toString()}
                    serverUuid={server.uuid}
                  />
                )}
              </GroupedRow>,
            ]
          })}
          <Link key="add-server" href="/server" asChild>
            <GroupedRow
              accessibilityLabel="Add server"
              icon={PlusIcon}
              title="Add server"
              onPress={() => {}}
              hideChevron
            />
          </Link>
        </GroupedSection>
        <GroupedSection
          title="Automatic rewind"
          footer="Storyteller can automatically rewind a few seconds after long breaks (a pause greater than five minutes) or audio interruptions (phone calls, voice assistants, navigation, etc.)."
        >
          <GroupedRow
            title="Enabled"
            trailing={
              <Switch
                accessibilityLabel="Automatic rewind enabled"
                checked={preferences.automaticRewind.enabled}
                onCheckedChange={(value) =>
                  updatePreference({
                    name: "automaticRewind",
                    value: {
                      ...preferences.automaticRewind,
                      enabled: value,
                    },
                  })
                }
              />
            }
          />
          <GroupedRow
            title="Long break"
            value={`${preferences.automaticRewind.afterBreak}s`}
            className="pb-2"
          >
            <Slider
              accessibilityLabel="Automatic rewind after long break"
              disabled={!preferences.automaticRewind.enabled}
              className="w-full"
              start={1}
              stop={30}
              step={1}
              value={preferences.automaticRewind.afterBreak}
              onValueChange={(value) => {
                updatePreference({
                  name: "automaticRewind",
                  value: {
                    ...preferences.automaticRewind,
                    // Rounding to hundredths to account for floating point errors
                    afterBreak: Math.round(value * 100) / 100,
                  },
                })
              }}
            />
          </GroupedRow>
          <GroupedRow
            title="Interruption"
            value={`${preferences.automaticRewind.afterInterruption}s`}
            className="pb-2"
          >
            <Slider
              accessibilityLabel="Automatic rewind after interruption"
              disabled={!preferences.automaticRewind.enabled}
              className="w-full"
              start={1}
              stop={30}
              step={1}
              value={preferences.automaticRewind.afterInterruption}
              onValueChange={(value) => {
                updatePreference({
                  name: "automaticRewind",
                  value: {
                    ...preferences.automaticRewind,
                    // Rounding to hundredths to account for floating point errors
                    afterInterruption: Math.round(value * 100) / 100,
                  },
                })
              }}
            />
          </GroupedRow>
        </GroupedSection>
        <ReadingSettings />
        {/* LOFI-FORK: the atmosphere's settings, see FORK.md */}
        <LofiAtmosphereSettings />
        <GroupedSection title="Logging">
          <GroupedRow
            accessibilityLabel={
              preferences.logLevel === "debug"
                ? "Disable debug logging"
                : "Enable debug logging"
            }
            title={`${preferences.logLevel === "debug" ? "Disable" : "Enable"} debug logging`}
            hideChevron
            onPress={() => {
              updatePreference({
                name: "logLevel",
                value:
                  preferences.logLevel === "debug"
                    ? __DEV__
                      ? "info"
                      : "error"
                    : "debug",
              })
            }}
          />
          <Link key="view-logs" href="/log" asChild>
            <GroupedRow
              accessibilityLabel="View logs"
              title="View logs"
              onPress={() => {}}
            />
          </Link>
        </GroupedSection>
        <GroupedSection
          title="About"
          footer={`Version ${Constants.expoConfig?.version}`}
        >
          <Link
            key="docs"
            href="https://storyteller-platform.dev/"
            asChild
          >
            <GroupedRow
              icon={BookOpenIcon}
              title="Documentation"
              trailing={externalIcon}
              onPress={() => {}}
            />
          </Link>
          <Link
            key="issue"
            href="https://gitlab.com/storyteller-platform/storyteller/-/issues/new?type=ISSUE"
            asChild
          >
            <GroupedRow
              icon={BugIcon}
              title="Report an issue"
              trailing={externalIcon}
              onPress={() => {}}
            />
          </Link>
          <Link key="discord" href="https://discord.gg/KhSvFqcrza" asChild>
            <GroupedRow
              leading={<DiscordIcon size={22} />}
              title="Join us on Discord"
              trailing={externalIcon}
              onPress={() => {}}
            />
          </Link>
        </GroupedSection>
      </ScrollView>
      {usesSystemHeader && (
        <Stack.Screen
          options={{ headerLargeTitle: true, headerTransparent: true }}
        />
      )}
      {/* Contributes header options, it does not render a view. */}
      <ScreenBackButton />
      <MiniPlayerWidget />
    </>
  )
}
