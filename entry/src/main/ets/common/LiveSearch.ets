/** Coalesce typing into one read; clearing restores the default immediately. */
export class LiveSearch {
  private timer: number = -1
  private revision: number = 0
  private queued: string | undefined = undefined
  private commit: () => void
  constructor(commit: () => void) { this.commit = commit }
  update(value: string): void {
    this.cancel()
    this.queued = value
    if (!value.trim()) { this.queued = undefined; this.commit(); return }
    const revision: number = this.revision
    this.timer = setTimeout(() => {
      this.timer = -1
      if (revision === this.revision) { this.queued = undefined; this.commit() }
    }, 280)
  }
  flush(): void { this.cancel(); this.commit() }
  pause(): void {
    this.revision++
    if (this.timer >= 0) clearTimeout(this.timer)
    this.timer = -1
  }
  resume(): void { if (this.queued !== undefined) this.update(this.queued) }
  cancel(): void {
    this.pause()
    this.queued = undefined
  }
}
