import { cn } from "@/lib/utils";

type InputProps = React.InputHTMLAttributes<HTMLInputElement> & {
  label?: string;
  error?: string;
};

// Plain field by default; pass `label` / `error` for a labelled form field.
export function Input({ className, label, error, id, ...props }: InputProps) {
  const field = (
    <input
      id={id}
      aria-invalid={error ? true : undefined}
      className={cn(
        "flex h-11 w-full rounded-xl border border-border bg-card px-3.5 text-sm text-foreground placeholder:text-muted",
        "focus:outline-2 focus:outline-offset-0 focus:outline-ring disabled:cursor-not-allowed disabled:opacity-50",
        error && "border-danger",
        className
      )}
      {...props}
    />
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
