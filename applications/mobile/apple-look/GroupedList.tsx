// LOFI-FORK: the Apple Podcasts look for the Books side (see FORK.md).
import { ChevronRightIcon, type LucideIcon } from "lucide-react-native"
import {
  Children,
  Fragment,
  type ReactElement,
  type ReactNode,
  isValidElement,
} from "react"
import { Platform, Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { cn } from "@/lib/utils"

/**
 * The classes for a screen that sits behind grouped lists: a light grey in
 * light mode and black in dark mode, so the white or dark grey cards stand out.
 */
export const groupedScreenClass = "bg-secondary dark:bg-background"

/** Whether the system is iOS 26 or newer, which rounds cards more. */
const isIOS26 =
  Platform.OS === "ios" && parseInt(String(Platform.Version), 10) >= 26

const ICON_INSET = 52
const TEXT_INSET = 16

type SectionProps = {
  /** A muted heading above the card, in sentence case. */
  title?: string | undefined
  /** Muted explanatory text under the card. */
  footer?: ReactNode
  className?: string | undefined
  /** The left inset of the separators, when rows are not plain GroupedRows. */
  separatorInset?: number
  children?: ReactNode
}

/**
 * Apple's inset grouped section: an optional heading, a rounded card holding
 * the rows with a separator between them, and an optional footer.
 */
export function GroupedSection({
  title,
  footer,
  className,
  separatorInset: fixedInset,
  children,
}: SectionProps) {
  const items = Children.toArray(children)

  return (
    <View className={cn("mt-6", className)}>
      {title ? (
        <Text
          accessibilityRole="header"
          className="text-muted-foreground mb-2 px-4 text-[13px]"
        >
          {title}
        </Text>
      ) : null}
      <View
        className={cn(
          "bg-card overflow-hidden",
          isIOS26 ? "rounded-[26px]" : "rounded-2xl",
        )}
      >
        {items.map((child, i) => {
          const next = items[i + 1]
          return (
            <Fragment key={isValidElement(child) ? child.key : i}>
              {child}
              {next ? (
                <Separator inset={fixedInset ?? separatorInset(next)} />
              ) : null}
            </Fragment>
          )
        })}
      </View>
      {footer ? (
        typeof footer === "string" ? (
          <Text className="text-muted-foreground mt-2 px-4 text-[13px]">
            {footer}
          </Text>
        ) : (
          <View className="mt-2 px-4">{footer}</View>
        )
      ) : null}
    </View>
  )
}

function separatorInset(next: unknown) {
  const props = isValidElement(next)
    ? (next as ReactElement<{ icon?: LucideIcon; leading?: ReactNode }>).props
    : undefined
  return props?.icon || props?.leading ? ICON_INSET : TEXT_INSET
}

function Separator({ inset }: { inset: number }) {
  return (
    <View
      className="bg-border h-px"
      style={{ marginLeft: inset }}
      importantForAccessibility="no-hide-descendants"
    />
  )
}

type RowProps = {
  /** The row's main text, 17 points. */
  title?: ReactNode
  /** A muted line under the title, 15 points. */
  subtitle?: ReactNode
  /** A muted value at the right, like "5s" or the current choice. */
  value?: ReactNode
  /** An icon at the left, drawn in the purple tint. */
  icon?: LucideIcon | undefined
  /** A custom view at the left, for icons that are not Lucide icons. */
  leading?: ReactNode
  /** A control at the right, such as a Switch. It replaces the chevron. */
  trailing?: ReactNode
  /** Makes the row tappable, with a chevron unless `trailing` is set. */
  onPress?: (() => void) | undefined
  /** Draws the title in the destructive colour. */
  destructive?: boolean | undefined
  /** Draws the title in the purple tint, like a text button. */
  tinted?: boolean | undefined
  disabled?: boolean | undefined
  accessibilityLabel?: string | undefined
  /** Hides the chevron on a tappable row, for rows that do not open a screen. */
  hideChevron?: boolean | undefined
  className?: string | undefined
  /** Content under the title line, for example a slider across the full width. */
  children?: ReactNode
}

/**
 * Apple's list row: at least 44 points high with 16 points of padding, a
 * leading icon, title and subtitle, a trailing value or control, and a
 * chevron when it can be pressed. Children are drawn under the title line.
 */
export function GroupedRow({
  title,
  subtitle,
  value,
  icon,
  leading,
  trailing,
  onPress,
  destructive,
  tinted,
  disabled,
  accessibilityLabel,
  hideChevron,
  className,
  children,
}: RowProps) {
  const showChevron = onPress && !trailing && !hideChevron
  const hasHeader =
    title != null || subtitle != null || value != null || trailing != null

  const content = (
    <>
      {hasHeader ? (
        <View className="min-h-[44px] flex-row items-center gap-3 py-2">
          {icon ? <Icon as={icon} size={22} className="text-primary" /> : null}
          {leading}
          <View className="flex-1">
            {title != null ? (
              <Text
                className={cn(
                  "text-[17px]",
                  destructive && "text-destructive",
                  tinted && "text-primary",
                  disabled && "opacity-50",
                )}
              >
                {title}
              </Text>
            ) : null}
            {subtitle != null ? (
              <Text className="text-muted-foreground text-[15px]">
                {subtitle}
              </Text>
            ) : null}
          </View>
          {value != null ? (
            <Text className="text-muted-foreground shrink-0 text-[17px]">
              {value}
            </Text>
          ) : null}
          {trailing}
          {showChevron ? (
            <Icon
              as={ChevronRightIcon}
              size={18}
              className="text-muted-foreground"
            />
          ) : null}
        </View>
      ) : null}
      {children}
    </>
  )

  if (onPress) {
    return (
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={accessibilityLabel}
        disabled={disabled}
        onPress={onPress}
        className={cn("active:bg-accent px-4", className)}
      >
        {content}
      </Pressable>
    )
  }

  return (
    <View
      accessibilityLabel={accessibilityLabel}
      accessible={accessibilityLabel ? true : undefined}
      className={cn("px-4", className)}
    >
      {content}
    </View>
  )
}
