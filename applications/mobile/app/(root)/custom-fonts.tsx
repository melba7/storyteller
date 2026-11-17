import { File } from "expo-file-system"
import { useRouter } from "expo-router"
import { ChevronDown, Trash2 } from "lucide-react-native"
import { View } from "react-native"
import { ScrollView } from "react-native-gesture-handler"
import Swipeable from "react-native-gesture-handler/ReanimatedSwipeable"

import { GroupedSection, groupedScreenClass } from "@/apple-look/GroupedList"
import { FontLoader } from "@/components/FontLoader"
import { LoadingView } from "@/components/LoadingView"
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion"
import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import {
  useGetGlobalPreferencesQuery,
  useUpdateGlobalPreferenceMutation,
} from "@/store/localApi"
import { getCustomFontUrl } from "@/store/persistence/fonts"

export default function CustomFontListScreen() {
  const { data: preferences, isLoading } = useGetGlobalPreferencesQuery()
  const [updatePreference] = useUpdateGlobalPreferenceMutation()

  const router = useRouter()

  if (isLoading) return <LoadingView />

  const customFonts = preferences?.customFonts ?? []

  return (
    <View className={`android:pt-safe w-full flex-1 ${groupedScreenClass}`}>
      <View className="mb-2 w-full flex-row items-center px-4 pt-3">
        <Button
          accessibilityLabel="Close custom fonts"
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
        Custom fonts
      </Text>
      <ScrollView className="flex-1" contentContainerClassName="px-4 pb-8">
        <FontLoader />
        <GroupedSection separatorInset={16}>
        {customFonts.map((font, index) => (
          <Swipeable
            key={font.name}
            renderRightActions={() => (
              <Button
                accessibilityLabel={`Delete custom font ${font.name}`}
                className="align-center h-full w-20 justify-center rounded-none sm:h-full"
                variant="destructive"
                onPress={() => {
                  if (preferences?.typography.fontFamily === font.name) {
                    updatePreference({
                      name: "customFonts",
                      value: "Literata",
                    })
                  }
                  updatePreference({
                    name: "customFonts",
                    value: customFonts.filter((_, i) => i !== index),
                  })

                  new File(getCustomFontUrl(font.filename)).delete()
                }}
              >
                <Icon as={Trash2} size={24} className="text-white" />
              </Button>
            )}
          >
            <Accordion type="single" collapsible>
              <AccordionItem value="item-1" className="bg-card border-b-0 px-4">
                <AccordionTrigger>
                  <Text
                    className="text-[17px] select-none"
                    style={{ fontFamily: font.name }}
                  >
                    {font.name}
                  </Text>
                </AccordionTrigger>
                <AccordionContent>
                  <Text
                    className="text-[15px] select-none"
                    style={{ fontFamily: font.name }}
                  >
                    The quick brown fox jumps over the lazy dog.
                  </Text>
                </AccordionContent>
              </AccordionItem>
            </Accordion>
          </Swipeable>
        ))}
        </GroupedSection>
      </ScrollView>
    </View>
  )
}
