import { cn } from "@/lib/utils";

type SelectProps = React.SelectHTMLAttributes<HTMLSelectElement> & {
  label?: string;
  error?: string;
};

// Same look as Input; pass `label` / `error` for a labelled form field.
export function Select({ className, label, error, id, children, ...props }: SelectProps) {
  const field = (
    <select
      id={id}
      aria-invalid={error ? true : undefined}
      className={cn(
        "flex h-11 w-full rounded-xl border border-border bg-card px-3 text-sm text-foreground",
        "focus:outline-2 focus:outline-offset-0 focus:outline-ring disabled:cursor-not-allowed disabled:opacity-50",
        error && "border-danger",
        className
      )}
      {...props}
    >
      {children}
    </select>
  );

  if (!label && !error) return field;

  return (
    <div className="flex flex-col gap-1.5">
      {label && (
        <label htmlFor={id} className="text-sm font-semibold text-foreground">
          {label}
        </label>
      )}
      {field}
      {error && (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      )}
    </div>
  );
}
