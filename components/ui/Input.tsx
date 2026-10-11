import { cn } from "@/lib/utils";

type InputProps = React.InputHTMLAttributes<HTMLInputElement> & {
  label?: string;
  error?: string;
};

// Shared field look (Input, Select, Textarea): 6px corners, a border at >= 3:1 against the field,
// 40px high on desktop and 44px below lg.
export const FIELD =
  "flex h-10 w-full rounded-md border border-field-border bg-card px-3 text-sm text-foreground placeholder:text-muted max-lg:h-11 " +
  "focus:border-ring focus:outline-2 focus:-outline-offset-1 focus:outline-ring " +
  "disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:border-danger";

export const FIELD_LABEL = "text-[13px] leading-5 font-medium text-foreground";
export const FIELD_ERROR = "text-[13px] leading-5 text-danger";

// Plain field by default; pass `label` / `error` for a labelled form field.
export function Input({ className, label, error, id, ...props }: InputProps) {
  const field = (
    <input
      id={id}
      aria-invalid={error ? true : undefined}
      className={cn(FIELD, className)}
      {...props}
    />
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

type TextareaProps = React.TextareaHTMLAttributes<HTMLTextAreaElement> & {
  label?: string;
  error?: string;
};

// Multi-line field with the same look as Input.
export function Textarea({ className, label, error, id, rows = 4, ...props }: TextareaProps) {
  const field = (
    <textarea
      id={id}
      rows={rows}
      aria-invalid={error ? true : undefined}
      className={cn(FIELD, "h-auto max-lg:h-auto py-2 leading-5", className)}
      {...props}
    />
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
