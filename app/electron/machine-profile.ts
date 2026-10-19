/** Web stub. The desktop module reads the OS via Electron; the renderer only needs the shape. */
export interface MachineProfile {
  ageDays: number | null
  arch: string
  locale: string
  platform: NodeJS.Platform
  release: string
  username: string
}
