"use client";

import { useId, useState } from "react";
import { cn } from "@/lib/utils";

export type TabItem = { id: string; label: string; content: React.ReactNode };

// Underline tabs: a hairline under the row, a 2px accent line under the selected tab.
export function Tabs({ tabs, className }: { tabs: TabItem[]; className?: string }) {
  const [active, setActive] = useState(tabs[0]?.id);
  const base = useId();
  const current = tabs.find((t) => t.id === active) ?? tabs[0];

  return (
    <div className={className}>
      <div role="tablist" className="flex gap-4 overflow-x-auto border-b border-border">
        {tabs.map((t) => {
          const selected = t.id === current?.id;
          return (
            <button
              key={t.id}
              type="button"
              role="tab"
              id={`${base}-tab-${t.id}`}
              aria-selected={selected}
              aria-controls={`${base}-panel-${t.id}`}
              onClick={() => setActive(t.id)}
              className={cn(
                "-mb-px h-10 whitespace-nowrap border-b-2 px-1 text-sm transition-colors max-lg:h-11",
                "focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-ring",
                selected
                  ? "border-accent-foreground font-semibold text-foreground"
                  : "border-transparent font-medium text-muted hover:text-foreground"
              )}
            >
              {t.label}
            </button>
          );
        })}
      </div>
      {current && (
        <div
          role="tabpanel"
          id={`${base}-panel-${current.id}`}
          aria-labelledby={`${base}-tab-${current.id}`}
          className="pt-4"
        >
          {current.content}
        </div>
      )}
    </div>
  );
}
