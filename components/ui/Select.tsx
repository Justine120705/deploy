import { cn } from "@/lib/utils";
import { FIELD, FIELD_ERROR, FIELD_LABEL } from "./Input";

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
      className={cn(FIELD, "pr-8", className)}
      {...props}
    >
      {children}
    </select>
  );

  if (!label && !error) return field;

  return (
    <div className="flex flex-col gap-1.5">
      {label && (
        <label htmlFor={id} className={FIELD_LABEL}>
          {label}
        </label>
      )}
      {field}
      {error && (
        <p role="alert" className={FIELD_ERROR}>
          {error}
        </p>
      )}
    </div>
  );
}
