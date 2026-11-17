// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { View } from "react-native"

import { Button } from "@/components/ui/button"
import { Text } from "@/components/ui/text"

import { addAudioFiles } from "./addAudioFiles"

/** Profile's "Add audio files": opens the Files app. They show up in "Your files". */
export function AddAudioFilesRow() {
  return (
    <View className="border-border gap-2 border-b py-3">
      <Text className="font-semibold">Your own audio files</Text>
      <Text className="text-muted-foreground text-sm">
        Add audio from the Files app. It plays offline, goes in Up Next and is
        transcribed like a download.
      </Text>
      <Button
        variant="outline"
        className="rounded-full"
        accessibilityLabel="Add audio files from the Files app"
        onPress={() => void addAudioFiles()}
      >
        <Text>Add audio files</Text>
      </Button>
    </View>
  )
}
