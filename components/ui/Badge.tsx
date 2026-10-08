import { cn } from "@/lib/utils";

export function Badge({ className, children, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div 
      className={cn("inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold text-white bg-slate-700 dark:bg-slate-600 transition-colors", className)} 
      {...props}
    >
      {children}
    </div>
  );
}