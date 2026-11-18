// LOFI-FORK: the podcasts section's themes (see FORK.md).
//
// Pure rules for the Podcasts section's look: the list of themes, the saved choice and which
// theme name the section uses for a choice. The colours themselves are in
// podcasts/themes.css (and global.css for light and dark); the saving is in
// podcasts/usePodcastsTheme.ts.

export type Scheme = "light" | "dark"

export type PodcastTheme = {
  /** The Uniwind theme name. */
  id: string
  /** What the listener sees. */
  name: string
  dark: boolean
  /** The two colours of the little picture in Profile; they match the CSS. */
  swatch: { background: string; accent: string }
}

export const THEMES: readonly PodcastTheme[] = [
  {
    id: "light",
    name: "Light",
    dark: false,
    swatch: { background: "#ffffff", accent: "#9b42f5" },
  },
  {
    id: "dark",
    name: "Dark",
    dark: true,
    swatch: { background: "#000000", accent: "#b57bff" },
  },
  {
    id: "pod-black",
    name: "Extra Dark",
    dark: true,
    swatch: { background: "#000000", accent: "#ef7f3e" },
  },
  {
    id: "pod-midnight",
    name: "Midnight",
    dark: true,
    swatch: { background: "#0b1426", accent: "#7aa7ff" },
  },
  {
    id: "pod-paper",
    name: "Paper",
    dark: false,
    swatch: { background: "#f4ecd8", accent: "#9a4a1a" },
  },
  {
    id: "pod-forest",
    name: "Forest",
    dark: true,
    swatch: { background: "#0d1a14", accent: "#6fcf8f" },
  },
]

/** The themes beyond light and dark: declared in themes.css and listed in metro.config.js. */
export const EXTRA_THEME_IDS: readonly string[] = THEMES.filter(
  (theme) => theme.id !== "light" && theme.id !== "dark",
).map((theme) => theme.id)

export function isDarkTheme(id: string): boolean {
  return THEMES.find((theme) => theme.id === id)?.dark ?? false
}

// MARK: The choice

export type ThemeMode =
  /** Whatever light or dark the rest of the app uses. */
  | "app"
  /** One theme, always. */
  | "theme"
  /** The light theme when iOS is light and the dark theme when iOS is dark. */
  | "ios"

export type ThemeChoice = {
  mode: ThemeMode
  /** Used in "theme" mode. */
  theme: string
  /** Used in "ios" mode when iOS is light. */
  lightTheme: string
  /** Used in "ios" mode when iOS is dark. */
  darkTheme: string
}

export const DEFAULT_CHOICE: ThemeChoice = {
  mode: "app",
  theme: "dark",
  lightTheme: "light",
  darkTheme: "dark",
}

const MODES: readonly ThemeMode[] = ["app", "theme", "ios"]

function known(value: unknown, dark: boolean | null): value is string {
  return THEMES.some(
    (theme) => theme.id === value && (dark === null || theme.dark === dark),
  )
}

/** The saved choice; a missing, broken or partial value falls back to the defaults. */
export function parseChoice(saved: string | null): ThemeChoice {
  if (!saved) return DEFAULT_CHOICE
  try {
    const value: unknown = JSON.parse(saved)
    if (typeof value !== "object" || value === null) return DEFAULT_CHOICE
    const record = value as Record<string, unknown>
    const mode = record["mode"]
    const theme = record["theme"]
    const lightTheme = record["lightTheme"]
    const darkTheme = record["darkTheme"]
    return {
      mode: MODES.find((each) => each === mode) ?? DEFAULT_CHOICE.mode,
      theme: known(theme, null) ? theme : DEFAULT_CHOICE.theme,
      lightTheme: known(lightTheme, false)
        ? lightTheme
        : DEFAULT_CHOICE.lightTheme,
      darkTheme: known(darkTheme, true) ? darkTheme : DEFAULT_CHOICE.darkTheme,
    }
  } catch {
    return DEFAULT_CHOICE
  }
}

export function serializeChoice(choice: ThemeChoice): string {
  return JSON.stringify(choice)
}

/**
 * The Uniwind theme the Podcasts section uses. `appScheme` is what the rest of the app shows
 * now; `systemScheme` is iOS's own setting (null when iOS does not say).
 */
export function resolveThemeName(
  choice: ThemeChoice,
  appScheme: Scheme,
  systemScheme: Scheme | null | undefined,
): string {
  if (choice.mode === "app") return appScheme
  if (choice.mode === "theme") return choice.theme
  return (systemScheme ?? appScheme) === "dark"
    ? choice.darkTheme
    : choice.lightTheme
}
