import { Link, useRouter } from "expo-router"
import { ChevronDown, Pencil, Plus, Trash2 } from "lucide-react-native"
import { View } from "react-native"
import { ScrollView } from "react-native-gesture-handler"
import Swipeable from "react-native-gesture-handler/ReanimatedSwipeable"

import { GroupedRow, GroupedSection, groupedScreenClass } from "@/apple-look/GroupedList"
import { LoadingView } from "@/components/LoadingView"
import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import {
  useGetGlobalPreferencesQuery,
  useUpdateGlobalPreferenceMutation,
} from "@/store/localApi"

export default function CustomThemeListScreen() {
  const { data: preferences, isLoading } = useGetGlobalPreferencesQuery()
  const [updatePreference] = useUpdateGlobalPreferenceMutation()

  const router = useRouter()

  if (isLoading) return <LoadingView />

  if (!preferences) return null

  const { colorThemes } = preferences

  return (
    <View className={`android:pt-safe w-full flex-1 ${groupedScreenClass}`}>
      <View className="mb-2 w-full flex-row items-center px-4 pt-3">
        <Button
          accessibilityLabel="Close custom themes"
          variant="ghost"
          size="icon"
          onPress={() => {
            router.back()
          }}
        >
          <Icon as={ChevronDown} size={24} />
        </Button>
      </View>
      <Text variant="h2" className="mx-4 mb-2 border-b-0 text-[28px] font-bold">
        Custom themes
      </Text>
      <ScrollView className="flex-1" contentContainerClassName="px-4 pb-8">
        <GroupedSection separatorInset={52}>
          <Link key="new" href="/custom-theme/new" asChild>
            <GroupedRow
              accessibilityLabel="Create new custom theme"
              icon={Plus}
              title="New theme"
              hideChevron
              onPress={() => {}}
            />
          </Link>
          {colorThemes.map((theme, index) => (
            <Swipeable
              key={theme.name}
              renderRightActions={() => (
                <Button
                  accessibilityLabel={`Delete custom theme ${theme.name}`}
                  className="align-center h-full w-20 justify-center rounded-none"
                  variant="destructive"
                  onPress={() => {
                    updatePreference({
                      name: "colorThemes",
                      value: colorThemes.filter((_, i) => i !== index),
                    })
                  }}
                >
                  <Icon as={Trash2} size={24} className="text-white" />
                </Button>
              )}
            >
              <Link
                href={{
                  pathname: "/custom-theme/[name]",
                  params: { name: theme.name },
                }}
                asChild
              >
                <GroupedRow
                  accessibilityLabel={`Edit custom theme ${theme.name}`}
                  icon={Pencil}
                  title={theme.name}
                  className="bg-card"
                  hideChevron
                  trailing={
                    <View className="flex-row gap-2">
                      <View
                        className="border-foreground/10 h-8 w-8 rounded-lg border"
                        style={{ backgroundColor: theme.foreground }}
                      />
                      <View
                        className="border-foreground/10 h-8 w-8 rounded-lg border"
                        style={{ backgroundColor: theme.background }}
                      />
                    </View>
                  }
                  onPress={() => {}}
                />
              </Link>
            </Swipeable>
          ))}
        </GroupedSection>
      </ScrollView>
    </View>
  )
}
