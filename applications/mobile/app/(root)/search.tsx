import { Search } from "lucide-react-native"
import { useState } from "react"
import { View } from "react-native"

import { BookGrid } from "@/components/BookGrid"
import { Icon } from "@/components/ui/icon"
import { Input } from "@/components/ui/input"
import { useBookSearch } from "@/hooks/useBookSearch"
import { usesSystemHeader } from "@/lib/nativeChrome"

export default function SearchScreen() {
  const [search, setSearch] = useState("")

  const results = useBookSearch(search)

  return (
    <BookGrid
      title="Search"
      books={results}
      refreshable={false}
      header={
        // On iOS the list's own side padding is 14, so 6 more makes the 20 inset.
        <View
          className={
            usesSystemHeader
              ? "mx-1.5 mb-2 justify-center"
              : "mx-safe-or-5 mb-2 justify-center"
          }
        >
          <Icon
            as={Search}
            size={18}
            className="text-muted-foreground pointer-events-none absolute left-3 z-10"
          />
          <Input
            className="w-auto pl-10"
            accessibilityLabel="Search books"
            autoFocus
            maxFontSizeMultiplier={2}
            value={search}
            onChangeText={setSearch}
            placeholder="Search"
            returnKeyType="search"
          />
        </View>
      }
    />
  )
}
