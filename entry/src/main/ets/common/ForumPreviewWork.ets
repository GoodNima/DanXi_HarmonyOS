import { FrameCallback, UIContext } from '@kit.ArkUI'

class PreviewIdleFrame extends FrameCallback {
  private action: (budget: number) => void
  constructor(action: (budget: number) => void) { super(); this.action = action }
  onIdle(budget: number): void { this.action(budget) }
}

class PreviewJob {
  id: number
  context: UIContext
  start: () => boolean
  constructor(id: number, context: UIContext, start: () => boolean) {
    this.id = id; this.context = context; this.start = start
  }
}

/** A feed-scoped queue, never a per-frame observed State or a gesture owner.
 * Web initialization is expensive even for offline HTML. Start the first
 * visible host on a frame; later hosts use idle time and wait for first layout.
 * Native List keeps all pan/fling events; this queue only defers optional work.
 */
export class ForumPreviewWork {
  private jobs: PreviewJob[] = []
  private nextId: number = 0
  private running: number = -1
  private expiry: number = -1
  private active: boolean = true
  private scrolling: boolean = false
  private pointers: Set<number> = new Set<number>()
  private version: number = 0
  private posted: boolean = false
  private firstHostStarted: boolean = false

  request(context: UIContext, start: () => boolean): number {
    const id: number = ++this.nextId
    this.jobs.push(new PreviewJob(id, context, start)); this.schedule()
    return id
  }

  finish(id: number): void {
    this.jobs = this.jobs.filter((job: PreviewJob) => job.id !== id)
    if (this.running === id) {
      if (this.expiry >= 0) clearTimeout(this.expiry)
      this.expiry = -1; this.running = -1
    }
    this.schedule()
  }

  setActive(active: boolean): void {
    this.active = active; this.invalidate()
    if (!active) { this.pointers.clear(); this.scrolling = false }
    else this.schedule()
  }

  touch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      for (const point of event.changedTouches) this.pointers.add(point.id)
      this.invalidate()
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (event.type === TouchType.Cancel) this.pointers.clear()
      else for (const point of event.changedTouches) this.pointers.delete(point.id)
      this.schedule()
    }
  }

  scrollStarted(): void { this.scrolling = true; this.invalidate() }
  scrollStopped(): void { this.scrolling = false; this.schedule() }

  private invalidate(): void { this.version++; this.posted = false }

  private schedule(): void {
    if (!this.active || this.scrolling || this.pointers.size > 0 || this.running >= 0 || this.posted || this.jobs.length === 0) return
    const version: number = this.version
    const job: PreviewJob = this.jobs[0]
    this.posted = true
    // The first prepared card gates a cold feed's reveal. Do not make that
    // one visible host depend on an idle budget that startup may never grant.
    // Further hosts remain idle-only; touches and inertia still cancel work.
    if (!this.firstHostStarted) {
      job.context.postFrameCallback({ onFrame: () => { this.startNext(version) }, onIdle: () => {} })
      return
    }
    job.context.postDelayedFrameCallback(new PreviewIdleFrame((budget: number) => {
      if (version !== this.version) return
      if (budget < 5000000) { this.posted = false; this.schedule(); return }
      this.startNext(version)
    }), 80)
  }

  private startNext(version: number): void {
    if (version !== this.version) return
    this.posted = false
    if (!this.active || this.scrolling || this.pointers.size > 0 || this.running >= 0) return
    const next: PreviewJob | undefined = this.jobs.shift()
    if (next === undefined) return
    this.running = next.id
    const first: boolean = !this.firstHostStarted
    // Set before invoking start: a synchronous layout completion must schedule
    // the following host at idle, rather than starting another on this frame.
    this.firstHostStarted = true
    this.expiry = setTimeout(() => { this.finish(next.id) }, 4000)
    if (!next.start()) {
      if (first) this.firstHostStarted = false
      this.finish(next.id)
    }
  }
}
