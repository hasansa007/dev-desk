import React from 'react';
import { getSystemStatus } from '@/lib/data';
import { StatusView } from '@/components/status/status-view';
import { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'System Status | Operational Health',
  description: 'Real-time telemetry and health monitoring for all core application services.',
};

/**
 * Server Component page route.
 * Strictly adheres to ARCHITECTURE.md:
 * - Server component by default (no "use client")
 * - Direct async call to lib/data.ts
 * - Clean error boundaries
 */
export default async function StatusPage() {
  const statusReport = await getSystemStatus();

  return (
    <main className="min-h-screen bg-gray-50 py-12 dark:bg-gray-950">
      <StatusView report={statusReport} />
    </main>
  );
}
