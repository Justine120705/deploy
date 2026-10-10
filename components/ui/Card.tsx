import { Icon, type IconKey } from "@/components/layout/Icon";
import { cn } from "@/lib/utils";
import { HUE_SOFT, HUE_TEXT, type Hue } from "./hue";

// Depth levels (docs/design/depth.md): "flat" sits on the page (inline panels), "base" is a normal
// content card (level 2), "raised" is a feature surface one step higher (level 3).
const ELEVATION = {
  flat: "shadow-none",
  base: "bg-card shadow-elev-sm",
  raised: "bg-card-raised shadow-elev-md",
} as const;

// `interactive`: only for a card that is itself one link or button (the whole surface acts). It lifts
// 2px on hover and shows the focus ring when anything inside has keyboard focus; no motion under
// prefers-reduced-motion.
const INTERACTIVE =
  "transition-[transform,box-shadow] duration-200 ease-out hover:-translate-y-0.5 hover:shadow-elev-md " +
  "has-focus-visible:outline-2 has-focus-visible:outline-offset-2 has-focus-visible:outline-ring " +
  "motion-reduce:transition-none motion-reduce:hover:translate-y-0";

export function Card({
  className,
  children,
  elevation = "base",
  interactive = false,
  ...props
}: React.HTMLAttributes<HTMLDivElement> & {
  elevation?: keyof typeof ELEVATION;
  interactive?: boolean;
}) {
  return (
    <div
      className={cn(
        "surface rounded-2xl border border-edge bg-card text-foreground",
        ELEVATION[elevation],
        interactive && INTERACTIVE,
        interactive && elevation === "raised" && "hover:shadow-elev-lg",
        className
      )}
      {...props}
    >
      {children}
    </div>
  );
}

// Title row used at the top of dashboard cards; `action` is the optional right-hand link or button.
// `icon` adds a small chip in the card's topic hue (see components/ui/hue.ts); the chip is as tall as
// the title line, so it does not change the card's height.
export function CardHeader({
  title,
  action,
  icon,
  hue = "violet",
  className,
}: {
  title: string;
  action?: React.ReactNode;
  icon?: IconKey;
  hue?: Hue;
  className?: string;
}) {
  return (
    <div className={cn("flex items-center justify-between gap-2", className)}>
      <div className="flex min-w-0 items-center gap-2">
        {icon && (
          <span
            aria-hidden="true"
            className={cn("flex size-[22px] shrink-0 items-center justify-center rounded-md", HUE_SOFT[hue], HUE_TEXT[hue])}
          >
            <Icon name={icon} className="size-3.5" />
          </span>
        )}
        <h2 className="truncate text-base font-bold leading-[22px]">{title}</h2>
      </div>
      {action}
    </div>
  );
}

export function StatCard({
  label,
  value,
  hint,
  className,
}: {
  label: string;
  value: React.ReactNode;
  hint?: string;
  className?: string;
}) {
  return (
    <Card className={cn("flex flex-col gap-1 p-5", className)}>
      <p className="text-sm font-medium text-muted">{label}</p>
      <p className="text-3xl font-extrabold">{value}</p>
      {hint && <p className="text-sm text-muted">{hint}</p>}
    </Card>
  );
}
