import { Icon, type IconKey } from "@/components/layout/Icon";
import { cn } from "@/lib/utils";
import { HUE_SOFT, HUE_TEXT, type Hue } from "./hue";

export function Card({ className, children, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn("rounded-xl border border-border bg-card text-foreground", className)}
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
