import { cn } from "@/lib/utils";

// primary = the one main action on a screen (lavender solid). accent = a soft secondary that still
// belongs to the brand. outline = the usual secondary. ghost = quiet tertiary. danger = destructive.
const variants = {
  primary: "bg-primary text-primary-foreground hover:bg-primary-hover",
  accent: "bg-accent text-accent-foreground hover:bg-lilac-soft",
  outline: "border border-border bg-card text-foreground hover:border-field-border hover:bg-hover-tint",
  ghost: "text-muted hover:bg-hover-tint hover:text-foreground",
  danger: "border border-danger/30 bg-danger-soft text-danger hover:border-danger/60",
} as const;

export type ButtonVariant = keyof typeof variants;

// 36px high on desktop, 44px below lg (touch). 6px corners.
export function Button({
  className,
  variant = "primary",
  type = "button",
  ...props
}: React.ButtonHTMLAttributes<HTMLButtonElement> & { variant?: ButtonVariant }) {
  return (
    <button
      type={type}
      className={cn(
        "inline-flex h-9 items-center justify-center gap-2 rounded-md px-3.5 text-sm font-semibold whitespace-nowrap transition-colors max-lg:h-11 max-lg:px-4",
        "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring",
        "disabled:pointer-events-none disabled:opacity-50",
        variants[variant],
        className
      )}
      {...props}
    />
  );
}
