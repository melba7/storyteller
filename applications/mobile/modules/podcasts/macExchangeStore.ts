// LOFI-FORK: the podcasts section's exchange with the Mac (see FORK.md).
//
// The last exchange with the Mac, kept in AsyncStorage so it survives a restart and the
// background task can write it too. A failure to read says nothing was saved; a failure to save
// is dropped, because the next run saves again. Not imported by any test (the rules are in
// macExchange.ts).
import AsyncStorage from "@react-native-async-storage/async-storage"
import { useEffect, useState } from "react"

import {
  type Came,
  type Exchange,
  type Went,
  exchangeToSave,
  parseExchange,
} from "./macExchange"

const KEY = "podcasts.macExchange"

export async function loadExchange(): Promise<Exchange | null> {
  try {
    return parseExchange(await AsyncStorage.getItem(KEY))
  } catch {
    return null
  }
}

/** Saves what a run did, when it changes what the screens say. */
export async function recordExchange(
  now: number,
  came: Came,
  went: Went,
): Promise<void> {
  try {
    const next = exchangeToSave(await loadExchange(), now, came, went)
    if (next !== null) await AsyncStorage.setItem(KEY, JSON.stringify(next))
  } catch (cause) {
    console.warn("Couldn't save the last exchange with the Mac", cause)
  }
}

/** The last exchange, read when the screen opens; null while reading and when there is none. */
export function useExchange(): Exchange | null {
  const [exchange, setExchange] = useState<Exchange | null>(null)
  useEffect(() => {
    let live = true
    void loadExchange().then((value) => {
      if (live) setExchange(value)
    })
    return () => {
      live = false
    }
  }, [])
  return exchange
}
