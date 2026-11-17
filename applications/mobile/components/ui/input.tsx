import {
  Platform,
  TextInput,
  type TextInputInstance,
  type TextInputProps,
} from "react-native"

import { cn } from "@/lib/utils"

function Input({
  className,
  placeholderClassName,
  ...props
}: TextInputProps &
  React.RefAttributes<TextInputInstance> & { placeholderClassName?: string }) {
  return (
    <TextInput
      className={cn(
        "bg-secondary text-foreground flex min-h-10 w-full min-w-0 flex-row items-center rounded-xl px-3 py-1 text-[17px] leading-5",
        props.editable === false &&
          cn(
            "opacity-50",
            Platform.select({
              web: "disabled:pointer-events-none disabled:cursor-not-allowed",
            }),
          ),
        Platform.select({
          web: cn(
            "selection:bg-primary selection:text-primary-foreground placeholder:text-muted-foreground transition-[color,box-shadow] outline-none",
            "focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-[3px]",
            "aria-invalid:ring-destructive/20 dark:aria-invalid:ring-destructive/40 aria-invalid:border-destructive",
          ),
          native: "placeholder:text-muted-foreground",
        }),
        className,
      )}
      {...props}
    />
  )
}

export { Input }
