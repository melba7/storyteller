import { router } from "expo-router"
import { CaseSensitive } from "lucide-react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { cn } from "@/lib/utils"
import { useAppSelector } from "@/store/appState"
import { getCurrentlyPlayingBookUuid } from "@/store/selectors/bookshelfSelectors"

type Props = {
  /** Colour class for the icon. */
  iconClassName?: string
}

export function SettingsItem({ iconClassName = "text-foreground" }: Props) {
  const bookUuid = useAppSelector(getCurrentlyPlayingBookUuid)

  return (
    <Button
      accessibilityLabel="Open reading settings"
      variant="ghost"
      size="icon"
      className="h-11 w-11 rounded-full sm:h-11 sm:w-11 items-center"
      disabled={!bookUuid}
      onPress={() => {
        if (!bookUuid) return

        router.push({
          pathname: "/reading-settings",
          params: { uuid: bookUuid },
        })
      }}
    >
      <Icon
        as={CaseSensitive}
        className={cn("mt-0.5 -mb-0.5", iconClassName)}
        size={24}
      />
    </Button>
  )
}
