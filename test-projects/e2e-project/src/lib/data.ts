import { SystemStatusReport } from './types';

/**
 * Server-only data access for system health metrics.
 * Conforms to ARCHITECTURE.md rule: all data access localized in src/lib/data.ts.
 */
export async function getSystemStatus(): Promise<SystemStatusReport> {
  // Simulate lightweight probe with real timestamp and uptime
  const uptime = process.uptime();
  const now = new Date().toISOString();

  return {
    environment: process.env.NODE_ENV || 'production',
    overallStatus: 'healthy',
    uptimeSeconds: Math.floor(uptime),
    timestamp: now,
    checks: [
      {
        id: 'api-gateway',
        name: 'API Gateway',
        status: 'healthy',
        latencyMs: 14,
        message: 'All endpoints accepting traffic normally',
        lastChecked: now,
      },
      {
        id: 'database',
        name: 'PostgreSQL Primary',
        status: 'healthy',
        latencyMs: 22,
        message: 'Connection pool responsive, replica lag < 10ms',
        lastChecked: now,
      },
      {
        id: 'cache',
        name: 'Redis Cache Layer',
        status: 'healthy',
        latencyMs: 3,
        message: 'Memory utilization 41%, hit ratio 94%',
        lastChecked: now,
      },
      {
        id: 'storage',
        name: 'Object Storage (S3)',
        status: 'healthy',
        latencyMs: 45,
        message: 'Read/write permissions validated',
        lastChecked: now,
      },
    ],
  };
}
