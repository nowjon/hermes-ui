/** Web stub. Packaged-update metrics stay in Electron; the renderer only needs the report shape. */
export type UpdateRunOutcome = 'success' | 'failed' | 'noop' | 'refused'
export type UpdateFailedStage = 'download' | 'verify' | 'apply' | 'restart' | 'other'
export interface UpdateRunReport {
  outcome: UpdateRunOutcome
  mechanism: string
  duration_ms: number
  failed_stage?: UpdateFailedStage
  from_commit_date?: number
}
