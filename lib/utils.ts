import { clsx, type ClassValue } from "clsx";
import { extendTailwindMerge } from "tailwind-merge";

// Teach the merger the custom shadows (app/globals.css), so shadow-elev-sm and shadow-xl are seen as
// the same property and the later one wins (instead of shadow-elev-sm being read as a shadow color).
const twMerge = extendTailwindMerge({
  extend: { theme: { shadow: ["elev-xs", "elev-sm", "elev-md", "elev-lg", "pill"] } },
});

// 1. Tailwind class merger (Prevents CSS conflicts in your components)
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

// 2. Date Formatter (Useful for displaying clearance dates or document requests)
export function formatDate(dateString: string | Date) {
  return new Date(dateString).toLocaleDateString("en-US", {
    month: "long",
    day: "numeric",
    year: "numeric",
  });
}

// 3. Currency Formatter (Useful for the Cashier module)
export function formatCurrency(amount: number) {
  return new Intl.NumberFormat("en-PH", {
    style: "currency",
    currency: "PHP",
  }).format(amount);
}