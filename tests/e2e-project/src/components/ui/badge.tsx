import React from 'react';
import { cn } from '@/lib/utils';
import { StatusLevel } from '@/lib/types';

interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement> {
  status?: StatusLevel;
}

export function Badge({ className, status = 'healthy', children, ...props }: BadgeProps) {
  const statusStyles: Record<StatusLevel, string> = {
    healthy: 'bg-emerald-100 text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300 border-emerald-300 dark:border-emerald-800',
    degraded: 'bg-amber-100 text-amber-800 dark:bg-amber-950 dark:text-amber-300 border-amber-300 dark:border-amber-800',
    critical: 'bg-rose-100 text-rose-800 dark:bg-rose-950 dark:text-rose-300 border-rose-300 dark:border-rose-800',
  };

  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-semibold uppercase tracking-wider',
        statusStyles[status],
        className
      )}
      {...props}
    >
      {children}
    </span>
  );
}
