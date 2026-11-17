import { type HrefObject, useRouter } from "expo-router"
import { FlatList } from "react-native-gesture-handler"

import { SectionHeader } from "@/apple-look/SectionHeader"
import { type BookWithRelations } from "@/database/books"

import { BookThumbnail } from "./BookThumbnail"
import { Stack } from "./ui/Stack"

interface Props {
  label: string
  href?: string | HrefObject | undefined
  books: BookWithRelations[]
}

export function Shelf({ label, href, books }: Props) {
  const router = useRouter()

  if (!books.length) return null

  return (
    <Stack className="gap-2">
      <SectionHeader
        title={label}
        className="px-5"
        {...(href
          ? {
              accessibilityLabel: `View all ${label} books`,
              onPress: () => router.push(href),
            }
          : {})}
      />

      <FlatList
        horizontal
        data={books.slice(0, 25)}
        contentContainerClassName="gap-3 px-5"
        renderItem={({ item: book }) => <BookThumbnail book={book} />}
      />
    </Stack>
  )
}
