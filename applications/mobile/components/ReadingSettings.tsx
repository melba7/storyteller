import { skipToken } from "@reduxjs/toolkit/query"
import deepmerge from "deepmerge"
import { dequal } from "dequal"
import { Link } from "expo-router"
import { useMemo } from "react"
import { View } from "react-native"

import { GroupedRow, GroupedSection } from "@/apple-look/GroupedList"
import { Switch } from "@/components/ui/switch"
import {
  type ReadaloudDecoratorStyle,
  defaultPreferences,
} from "@/database/preferencesTypes"
import { formatNumber } from "@/formatting"
import {
  useGetBookPreferencesQuery,
  useGetGlobalPreferencesQuery,
  useSetBookPreferencesAsDefaultsMutation,
  useUpdateBookPreferenceMutation,
  useUpdateGlobalPreferenceMutation,
} from "@/store/localApi"
import { type UUID } from "@/uuid"

import { ColorPickerDialog } from "./ColorPickerDialog"
import { LoadingView } from "./LoadingView"
import { ButtonGroup, ButtonGroupButton } from "./ui/ButtonGroup"
import { Select, SelectItem, SelectTrigger, SelectValue } from "./ui/select"
import { Slider } from "./ui/slider"
import { Text } from "./ui/text"

type Props = {
  bookUuid?: UUID
}

function getFontPreviewFamily(fontFamily: string) {
  switch (fontFamily) {
    case "Literata":
      return "Literata_500Medium"
    case "OpenDyslexic":
      return "OpenDyslexic-Regular"
    default:
      return fontFamily
  }
}

export function ReadingSettings({ bookUuid }: Props) {
  const { data: globalPreferences } = useGetGlobalPreferencesQuery()

  const { data: bookPreferences } = useGetBookPreferencesQuery(
    bookUuid ? { uuid: bookUuid } : skipToken,
  )

  const [updateGlobalPreference] = useUpdateGlobalPreferenceMutation()
  const [updateBookPreference] = useUpdateBookPreferenceMutation()
  const [setBookPreferencesAsDefaults] =
    useSetBookPreferencesAsDefaultsMutation()

  const preferences = useMemo(
    () =>
      bookPreferences
        ? globalPreferences && deepmerge(globalPreferences, bookPreferences)
        : globalPreferences,
    [globalPreferences, bookPreferences],
  )

  const dirty = useMemo(
    () => dequal(globalPreferences, preferences),
    [globalPreferences, preferences],
  )

  const typographyPreferencesAreDefaults = useMemo(
    () => dequal(preferences?.typography, defaultPreferences.typography),
    [preferences?.typography],
  )

  if (!preferences) return <LoadingView />

  const readaloudDecoratorStyle =
    preferences.readaloudDecoratorStyle ??
    defaultPreferences.readaloudDecoratorStyle

  // Writes a layout or typography change to the book when there is one, else to the defaults.
  const update = <Name extends "layout" | "typography">(
    name: Name,
    value: (typeof preferences)[Name],
  ) => {
    if (bookUuid) {
      updateBookPreference({ bookUuid, name, value })
    } else {
      updateGlobalPreference({ name, value })
    }
  }

  return (
    <View>
      <GroupedSection title="Appearance">
        <GroupedRow
          title="Dark mode"
          trailing={
            <ButtonGroup
              value={preferences.darkMode}
              onChange={(value: boolean | "auto") => {
                updateGlobalPreference({ name: "darkMode", value })
              }}
            >
              <ButtonGroupButton
                accessibilityLabel="Use light mode"
                value={false}
              >
                <Text maxFontSizeMultiplier={1}>Light</Text>
              </ButtonGroupButton>
              <ButtonGroupButton
                accessibilityLabel="Use device dark mode setting"
                value="auto"
              >
                <Text maxFontSizeMultiplier={1}>Device</Text>
              </ButtonGroupButton>
              <ButtonGroupButton
                accessibilityLabel="Use dark mode"
                value={true}
              >
                <Text maxFontSizeMultiplier={1}>Dark</Text>
              </ButtonGroupButton>
            </ButtonGroup>
          }
        />
        <GroupedRow
          title="Light theme"
          trailing={
            <Select
              value={{
                value: preferences.lightTheme,
                label: preferences.lightTheme,
              }}
              onValueChange={(option) => {
                if (!option) return
                updateGlobalPreference({
                  name: "lightTheme",
                  value: option.value,
                })
              }}
            >
              <SelectTrigger
                accessibilityLabel={`Light theme, ${preferences.lightTheme}`}
              >
                <SelectValue placeholder="" />
              </SelectTrigger>
              {preferences.colorThemes
                .filter(({ isDark }) => !isDark)
                .map(({ name }) => (
                  <SelectItem key={name} label={name} value={name} />
                ))}
            </Select>
          }
        />
        <GroupedRow
          title="Dark theme"
          trailing={
            <Select
              value={{
                value: preferences.darkTheme,
                label: preferences.darkTheme,
              }}
              onValueChange={(option) => {
                if (!option) return
                updateGlobalPreference({
                  name: "darkTheme",
                  value: option.value,
                })
              }}
            >
              <SelectTrigger
                accessibilityLabel={`Dark theme, ${preferences.darkTheme}`}
              >
                <SelectValue placeholder="" />
              </SelectTrigger>
              {preferences.colorThemes
                .filter(({ isDark }) => isDark)
                .map(({ name }) => (
                  <SelectItem key={name} label={name} value={name} />
                ))}
            </Select>
          }
        />
        <Link key="themes" href="/custom-theme" asChild>
          <GroupedRow
            accessibilityLabel="Manage custom themes"
            title="Manage custom themes"
            onPress={() => {}}
          />
        </Link>
        <GroupedRow
          title="Readaloud decoration"
          trailing={
            <ButtonGroup
              value={readaloudDecoratorStyle}
              onChange={(value: ReadaloudDecoratorStyle) => {
                if (bookUuid) {
                  updateBookPreference({
                    bookUuid,
                    name: "readaloudDecoratorStyle",
                    value,
                  })
                } else {
                  updateGlobalPreference({
                    name: "readaloudDecoratorStyle",
                    value,
                  })
                }
              }}
            >
              <ButtonGroupButton
                accessibilityLabel="Use highlight readaloud decoration"
                size="sm"
                value="highlight"
              >
                <Text maxFontSizeMultiplier={1.5}>Highlight</Text>
              </ButtonGroupButton>
              <ButtonGroupButton
                accessibilityLabel="Use underline readaloud decoration"
                size="sm"
                value="underline"
              >
                <Text maxFontSizeMultiplier={1.5}>Underline</Text>
              </ButtonGroupButton>
            </ButtonGroup>
          }
        />
        {readaloudDecoratorStyle === "highlight" ? (
          <GroupedRow
            title="Highlight color"
            trailing={
              <ColorPickerDialog
                key={preferences.readaloudColor}
                initialValue={preferences.readaloudColor}
                onSave={(value) => {
                  if (bookUuid) {
                    updateBookPreference({
                      bookUuid,
                      name: "readaloudColor",
                      value,
                    })
                  } else {
                    updateGlobalPreference({ name: "readaloudColor", value })
                  }
                }}
              />
            }
          />
        ) : null}
        <GroupedRow
          title="Floating toolbars"
          trailing={
            <Switch
              checked={preferences.floatingToolbar}
              onCheckedChange={(value) =>
                updateGlobalPreference({
                  name: "floatingToolbar",
                  value,
                })
              }
            />
          }
        />
      </GroupedSection>
      <GroupedSection title="Margins">
        <GroupedRow
          title="Left margin"
          value={`${preferences.layout.marginLeft ?? 0}px`}
          className="pb-2"
        >
          <Slider
            accessibilityLabel="Left margin"
            className="w-full"
            start={0}
            stop={50}
            step={1}
            value={preferences.layout.marginLeft ?? 0}
            onValueChange={(value) => {
              update("layout", {
                ...preferences.layout,
                marginLeft: Math.round(value),
              })
            }}
          />
        </GroupedRow>
        <GroupedRow
          title="Right margin"
          value={`${preferences.layout.marginRight ?? 0}px`}
          className="pb-2"
        >
          <Slider
            accessibilityLabel="Right margin"
            className="w-full"
            start={0}
            stop={50}
            step={1}
            value={preferences.layout.marginRight ?? 0}
            onValueChange={(value) => {
              update("layout", {
                ...preferences.layout,
                marginRight: Math.round(value),
              })
            }}
          />
        </GroupedRow>
      </GroupedSection>
      <GroupedSection title="Layout">
        <GroupedRow
          title="Reader layout"
          trailing={
            <ButtonGroup
              value={preferences.layout.scroll ? "scroll" : "page"}
              onChange={(layout: "page" | "scroll") => {
                update("layout", {
                  ...preferences.layout,
                  scroll: layout === "scroll",
                })
              }}
            >
              <ButtonGroupButton
                accessibilityLabel="Use page layout"
                value="page"
              >
                <Text maxFontSizeMultiplier={1}>Page</Text>
              </ButtonGroupButton>
              <ButtonGroupButton
                accessibilityLabel="Use scroll layout"
                value="scroll"
              >
                <Text maxFontSizeMultiplier={1}>Scroll</Text>
              </ButtonGroupButton>
            </ButtonGroup>
          }
        />
      </GroupedSection>
      <GroupedSection title={`Typography${!bookUuid ? " defaults" : ""}`}>
        {bookUuid ? (
          <GroupedRow
            key="set-defaults"
            accessibilityLabel="Set typography as defaults"
            title="Set as defaults"
            tinted
            hideChevron
            disabled={dirty}
            onPress={() => {
              setBookPreferencesAsDefaults({ bookUuid })
            }}
          />
        ) : null}
        {bookUuid ? (
          <GroupedRow
            key="reset-book"
            accessibilityLabel="Reset typography to defaults"
            title="Reset to defaults"
            tinted
            hideChevron
            disabled={typographyPreferencesAreDefaults}
            onPress={() => {
              updateBookPreference({
                bookUuid,
                name: "typography",
                value: {},
              })
            }}
          />
        ) : (
          <GroupedRow
            key="reset-global"
            accessibilityLabel="Reset typography settings"
            title="Reset"
            tinted
            hideChevron
            disabled={typographyPreferencesAreDefaults}
            onPress={() => {
              updateGlobalPreference({
                name: "typography",
                value: defaultPreferences.typography,
              })
            }}
          />
        )}
        <GroupedRow
          title="Font scaling"
          value={`${formatNumber(preferences.typography.scale, 2)}x`}
          className="pb-2"
        >
          <Slider
            accessibilityLabel="Font scaling"
            className="w-full"
            start={0.7}
            stop={2}
            step={0.05}
            value={preferences.typography.scale}
            onValueChange={(value) => {
              update("typography", {
                ...preferences.typography,
                // Rounding to hundredths to account for floating point errors
                scale: Math.round(value * 100) / 100,
              })
            }}
          />
        </GroupedRow>
        <GroupedRow
          title="Line height"
          value={`${formatNumber(preferences.typography.lineHeight, 2)}x`}
          className="pb-2"
        >
          <Slider
            accessibilityLabel="Line height"
            className="w-full"
            start={1.0}
            stop={2.0}
            step={0.05}
            value={preferences.typography.lineHeight}
            onValueChange={(value) => {
              update("typography", {
                ...preferences.typography,
                // Rounding to hundredths to account for floating point errors
                lineHeight: Math.round(value * 100) / 100,
              })
            }}
          />
        </GroupedRow>
        <GroupedRow
          title="Text alignment"
          trailing={
            <ButtonGroup
              value={preferences.typography.alignment}
              onChange={(value: "justify" | "left") => {
                update("typography", {
                  ...preferences.typography,
                  alignment: value,
                })
              }}
            >
              <ButtonGroupButton
                accessibilityLabel="Justify text alignment"
                value="justify"
              >
                <Text maxFontSizeMultiplier={1}>Justify</Text>
              </ButtonGroupButton>
              <ButtonGroupButton
                accessibilityLabel="Use left text alignment"
                value="left"
              >
                <Text maxFontSizeMultiplier={1}>Left</Text>
              </ButtonGroupButton>
            </ButtonGroup>
          }
        />
        <GroupedRow
          title="Font family"
          trailing={
            <Select
              value={{
                value: preferences.typography.fontFamily,
                label: preferences.typography.fontFamily,
              }}
              onValueChange={(option) => {
                if (!option) return
                update("typography", {
                  ...preferences.typography,
                  fontFamily: option.value,
                })
              }}
            >
              <SelectTrigger
                accessibilityLabel={`Font family, ${preferences.typography.fontFamily}`}
              >
                <SelectValue
                  placeholder=""
                  style={{
                    fontFamily: getFontPreviewFamily(
                      preferences.typography.fontFamily,
                    ),
                  }}
                />
              </SelectTrigger>
              <SelectItem label="Literata" value="Literata" />
              <SelectItem label="OpenDyslexic" value="OpenDyslexic" />
              {preferences.customFonts.map(({ name }) => (
                <SelectItem key={name} label={name} value={name} />
              ))}
            </Select>
          }
        />
        <Link key="fonts" href="custom-fonts" asChild>
          <GroupedRow
            accessibilityLabel="Manage custom fonts"
            title="Manage custom fonts"
            onPress={() => {}}
          />
        </Link>
      </GroupedSection>
    </View>
  )
}
