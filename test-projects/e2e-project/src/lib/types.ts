export type StatusLevel = 'healthy' | 'degraded' | 'critical';

export interface SubsystemCheck {
  id: string;
  name: string;
  status: StatusLevel;
  latencyMs: number;
  message: string;
  lastChecked: string;
}

export interface SystemStatusReport {
  environment: string;
  overallStatus: StatusLevel;
  uptimeSeconds: number;
  timestamp: string;
  checks: SubsystemCheck[];
}
