import { cn } from "@/lib/utils";

export function Card({ className, children, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div 
      className={cn("rounded-xl border bg-white dark:bg-slate-900 text-slate-950 dark:text-slate-50 shadow-sm", className)} 
      {...props}
    >
      {children}
    </div>
  );
}