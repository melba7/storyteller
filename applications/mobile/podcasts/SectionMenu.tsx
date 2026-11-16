// LOFI-FORK: the side menu with Books and Podcasts (see FORK.md).
import { useRouter } from "expo-router"
import { BookOpen, Menu as MenuIcon, Podcast } from "lucide-react-native"
import { useRef, useState } from "react"
import {
  Animated,
  Modal,
  Pressable,
  View,
  useWindowDimensions,
} from "react-native"
import { useReducedMotion } from "react-native-reanimated"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { cn } from "@/lib/utils"

export type Section = "books" | "podcasts"

const SECTIONS: { id: Section; label: string; icon: typeof BookOpen }[] = [
  { id: "books", label: "Books", icon: BookOpen },
  { id: "podcasts", label: "Podcasts", icon: Podcast },
]

const SLIDE_MS = 220

interface Props {
  /** The section this screen belongs to; it is highlighted in the menu. */
  current: Section
}

/**
 * The menu button at the top left of the Books and Podcasts screens. It opens a panel that
 * slides in from the left over a dimmed screen: Books and Podcasts, the current one
 * highlighted. A tap outside the panel closes it.
 */
export function SectionMenuButton({ current }: Props) {
  const router = useRouter()
  const { width } = useWindowDimensions()
  const reduceMotion = useReducedMotion()
  const panelWidth = Math.min(300, Math.round(width * 0.8))

  const [mounted, setMounted] = useState(false)
  // 0 is closed, 1 is open.
  const progress = useRef(new Animated.Value(0)).current

  function animateTo(value: 0 | 1, done?: () => void) {
    if (reduceMotion) {
      progress.setValue(value)
      done?.()
      return
    }
    Animated.timing(progress, {
      toValue: value,
      duration: SLIDE_MS,
      useNativeDriver: true,
    }).start(() => done?.())
  }

  function open() {
    setMounted(true)
    animateTo(1)
  }

  /** Slides the panel out, then goes where the listener chose (the screen change waits for the modal to leave). */
  function close(after?: () => void) {
    animateTo(0, () => {
      setMounted(false)
      after?.()
    })
  }

  function choose(section: Section) {
    if (section === current) {
      close()
    } else if (section === "podcasts") {
      close(() => router.push("/podcasts"))
    } else {
      // Back to the Books home that is already at the bottom, without stacking another.
      close(() => router.dismissTo("/"))
    }
  }

  return (
    <>
      <Button
        variant="ghost"
        size="icon"
        accessibilityLabel="Open the section menu"
        onPress={open}
      >
        <Icon as={MenuIcon} size={24} className="text-primary" />
      </Button>
      <Modal
        visible={mounted}
        transparent
        animationType="none"
        onRequestClose={() => close()}
      >
        <View className="flex-1">
          <Animated.View
            className="absolute top-0 right-0 bottom-0 left-0 bg-black/40"
            style={{ opacity: progress }}
          >
            <Pressable
              className="flex-1"
              accessibilityRole="button"
              accessibilityLabel="Close the section menu"
              onPress={() => close()}
            />
          </Animated.View>
          <Animated.View
            className="bg-background border-border pt-safe pl-safe absolute top-0 bottom-0 left-0 border-r"
            style={{
              width: panelWidth,
              transform: [
                {
                  translateX: progress.interpolate({
                    inputRange: [0, 1],
                    outputRange: [-panelWidth, 0],
                  }),
                },
              ],
            }}
          >
            <View className="gap-1 p-3">
              {SECTIONS.map((section) => (
                <Pressable
                  key={section.id}
                  className={cn(
                    "active:bg-secondary min-h-12 flex-row items-center gap-3 rounded-md px-3",
                    section.id === current && "bg-secondary",
                  )}
                  accessibilityRole="button"
                  accessibilityLabel={section.label}
                  accessibilityState={{ selected: section.id === current }}
                  onPress={() => choose(section.id)}
                >
                  <Icon
                    as={section.icon}
                    size={22}
                    className={
                      section.id === current
                        ? "text-primary"
                        : "text-muted-foreground"
                    }
                  />
                  <Text
                    className={cn(
                      "text-base",
                      section.id === current && "font-semibold",
                    )}
                  >
                    {section.label}
                  </Text>
                </Pressable>
              ))}
            </View>
          </Animated.View>
        </View>
      </Modal>
    </>
  )
}
