import { type VariantProps, cva } from "class-variance-authority"
import { Platform, Pressable } from "react-native"

import { TextClassContext } from "@/components/ui/text"
import { cn } from "@/lib/utils"

const buttonVariants = cva(
  cn(
    "group shrink-0 flex-row items-center justify-center gap-2 rounded-full shadow-none active:opacity-70",
    Platform.select({
      web: "focus-visible:border-ring focus-visible:ring-ring/50 aria-invalid:ring-destructive/20 dark:aria-invalid:ring-destructive/40 aria-invalid:border-destructive whitespace-nowrap outline-none transition-all focus-visible:ring-[3px] disabled:pointer-events-none [&_svg:not([class*='size-'])]:size-4 [&_svg]:pointer-events-none [&_svg]:shrink-0",
    }),
  ),
  {
    variants: {
      variant: {
        default: cn(
          "bg-primary",
          Platform.select({ web: "hover:bg-primary/90" }),
        ),
        destructive: cn(
          "bg-destructive",
          Platform.select({
            web: "hover:bg-destructive/90 focus-visible:ring-destructive/20 dark:focus-visible:ring-destructive/40",
          }),
        ),
        outline: cn(
          "border-border border bg-transparent",
          Platform.select({
            web: "hover:bg-accent",
          }),
        ),
        secondary: cn(
          "bg-primary/15",
          Platform.select({ web: "hover:bg-primary/20" }),
        ),
        ghost: Platform.select({
          web: "hover:bg-accent dark:hover:bg-accent/50",
        }),
        link: "",
      },
      size: {
        default: cn(
          "h-11 px-5 py-2",
          Platform.select({ web: "has-[>svg]:px-4" }),
        ),
        sm: cn(
          "h-[34px] gap-1.5 px-4",
          Platform.select({ web: "has-[>svg]:px-3" }),
        ),
        lg: cn("h-[50px] px-6", Platform.select({ web: "has-[>svg]:px-5" })),
        icon: "h-11 w-11",
        flex: "min-h-11 px-5 py-2",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  },
)

const buttonTextVariants = cva(
  cn(
    "text-foreground text-[17px] font-semibold",
    Platform.select({ web: "pointer-events-none transition-colors" }),
  ),
  {
    variants: {
      variant: {
        default: "text-primary-foreground",
        destructive: "text-white",
        outline: "text-foreground",
        secondary: "text-primary",
        ghost: "text-primary",
        link: cn(
          "text-primary font-normal group-active:underline",
          Platform.select({
            web: "underline-offset-4 hover:underline group-hover:underline",
          }),
        ),
      },
      size: {
        default: "",
        sm: "text-[15px]",
        lg: "",
        icon: "",
        flex: "",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  },
)

type ButtonProps = React.ComponentProps<typeof Pressable> &
  React.RefAttributes<typeof Pressable> &
  VariantProps<typeof buttonVariants>

function Button({
  accessibilityRole = "button",
  className,
  variant,
  size,
  ...props
}: ButtonProps) {
  return (
    <TextClassContext.Provider value={buttonTextVariants({ variant, size })}>
      <Pressable
        accessibilityRole={accessibilityRole}
        className={cn(
          props.disabled && "opacity-50",
          buttonVariants({ variant, size }),
          className,
        )}
        role="button"
        {...props}
      />
    </TextClassContext.Provider>
  )
}

export { Button, buttonTextVariants, buttonVariants }
export type { ButtonProps }
