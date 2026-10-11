import { cn } from "@/lib/utils";

// Small status tag: tint + strong text (>= 5.8:1 in both themes). The word is always there; colour only
// reinforces it. 6px corners, never a pill.
const tones = {
  success: "bg-success-soft text-success",
  warning: "bg-warning-soft text-warning",
  danger: "bg-danger-soft text-danger",
  info: "bg-info-soft text-info",
  neutral: "bg-neutral-soft text-neutral",
} as const;

export type BadgeTone = keyof typeof tones;

export function Badge({
  className,
  tone = "neutral",
  children,
  ...props
}: React.HTMLAttributes<HTMLSpanElement> & { tone?: BadgeTone }) {
  return (
    <span
      className={cn(
        "inline-flex h-6 items-center gap-1 rounded-md px-2 text-xs font-medium whitespace-nowrap",
        tones[tone],
        className
      )}
      {...props}
    >
      {children}
    </span>
  );
}

// Status values used across the database (clearance, payments, requests, holds, grades).
const STATUS_TONE: Record<string, BadgeTone> = {
  Cleared: "success",
  Approved: "success",
  Paid: "success",
  Passed: "success",
  Ready: "success",
  Released: "success",
  Active: "success",
  Saved: "success",
  Pending: "warning",
  Processing: "warning",
  Unsaved: "warning",
  Unpaid: "danger",
  Rejected: "danger",
  Failed: "danger",
  Invalid: "danger",
  Lifted: "neutral",
  Waived: "neutral",
};

export function statusTone(status: string): BadgeTone {
  return STATUS_TONE[status] ?? "neutral";
}

export function StatusBadge({ status, className }: { status: string; className?: string }) {
  return (
    <Badge tone={statusTone(status)} className={className}>
      {status}
    </Badge>
  );
}
