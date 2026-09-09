import React from 'react';
import { SystemStatusReport } from '@/lib/types';
import { Card, CardContent, CardHeader, CardTitle } from '@/lib/../components/ui/card';
import { Badge } from '@/lib/../components/ui/badge';
import { formatUptime } from '@/lib/utils';

interface StatusViewProps {
  report: SystemStatusReport;
}

/**
 * Server Component rendering system telemetry.
 * Conforms to ARCHITECTURE.md: default to server components, no unnecessary hooks.
 */
export function StatusView({ report }: StatusViewProps) {
  return (
    <div className="mx-auto max-w-4xl space-y-6 p-6">
      {/* Banner */}
      <div className="flex items-center justify-between rounded-xl border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-800 dark:bg-gray-900">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-50">System Operational Status</h1>
          <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">
            Environment: <span className="font-mono font-medium text-gray-700 dark:text-gray-300">{report.environment}</span> · Last checked: {new Date(report.timestamp).toLocaleTimeString()}
          </p>
        </div>
        <Badge status={report.overallStatus}>
          {report.overallStatus}
        </Badge>
      </div>

      {/* Overview Stats */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <Card>
          <CardHeader>
            <CardTitle>System Uptime</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-bold text-gray-900 dark:text-white">{formatUptime(report.uptimeSeconds)}</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Active Subsystems</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-bold text-gray-900 dark:text-white">{report.checks.length} / {report.checks.length} Online</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Average Latency</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-bold text-gray-900 dark:text-white">
              {Math.round(report.checks.reduce((acc, c) => acc + c.latencyMs, 0) / report.checks.length)} ms
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Subsystem Health Grid */}
      <Card>
        <CardHeader>
          <CardTitle>Subsystem Health Matrix</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="divide-y divide-gray-200 dark:divide-gray-800">
            {report.checks.map((check) => (
              <div key={check.id} className="flex items-center justify-between py-4 first:pt-0 last:pb-0">
                <div className="space-y-1">
                  <div className="flex items-center space-x-3">
                    <span className="font-semibold text-gray-900 dark:text-gray-100">{check.name}</span>
                    <Badge status={check.status}>{check.status}</Badge>
                  </div>
                  <p className="text-xs text-gray-500 dark:text-gray-400">{check.message}</p>
                </div>
                <div className="text-right">
                  <span className="font-mono text-xs text-gray-500 dark:text-gray-400">{check.latencyMs}ms</span>
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
