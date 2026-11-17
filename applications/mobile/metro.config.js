const { getSentryExpoConfig } = require("@sentry/react-native/metro")
const { getDefaultConfig } = require("expo/metro-config")
const { withUniwindConfig } = require("uniwind/metro")

const config = process.env.EXPO_PUBLIC_ENABLE_SENTRY
  ? getSentryExpoConfig(__dirname)
  : getDefaultConfig(__dirname)

module.exports = withUniwindConfig(config, {
  cssEntryFile: "./global.css",
  // LOFI-FORK: the Podcasts section's extra themes, declared in podcasts/themes.css (see FORK.md).
  extraThemes: ["pod-black", "pod-midnight", "pod-paper", "pod-forest"],
})
