import { UIContext } from '@kit.ArkUI'

class PreviewRevealEntry {
  ticket: number
  ready: boolean = false
  released: boolean = false
  show: (immediate: boolean) => void
  constructor(ticket: number, show: (immediate: boolean) => void) { this.ticket = ticket; this.show = show }
}

/** Reveal the prepared prefix in display order, including pinned/search rows.
 * Native List supplies the first visible index so recycled offscreen rows do
 * not hold up the viewport. No observed per-frame state or layout mutation. */
export class ForumPreviewSequence {
  private order: string[] = []
  private entries: Map<string, PreviewRevealEntry> = new Map<string, PreviewRevealEntry>()
  // A row's appearance belongs to the feed, not to a disposable lazy component.
  private revealed: Set<string> = new Set<string>()
  private browsed: boolean = false
  private context: UIContext | undefined = undefined
  private start: number = 0
  private nextTicket: number = 0
  private generation: number = 0
  private posted: boolean = false

  setOrder(keys: string[], startAtTop: boolean = false): void {
    this.order = keys.slice()
    const current: Set<string> = new Set<string>(keys)
    for (const key of this.entries.keys()) {
      if (!current.has(key)) this.entries.delete(key)
    }
    for (const key of this.revealed) {
      if (!current.has(key)) this.revealed.delete(key)
    }
    if (startAtTop) this.browsed = false
    this.start = startAtTop ? 0 : Math.min(this.start, Math.max(0, keys.length - 1))
    this.schedule()
  }

  hasRevealed(key: string): boolean { return this.revealed.has(key) }

  beginBrowsing(): void {
    if (this.browsed) return
    this.browsed = true
    this.schedule()
  }

  join(key: string, context: UIContext, show: (immediate: boolean) => void): number {
    const ticket: number = ++this.nextTicket
    this.context = context
    this.entries.set(key, new PreviewRevealEntry(ticket, show))
    this.schedule()
    return ticket
  }

  leave(key: string, ticket: number): void {
    if (this.entries.get(key)?.ticket === ticket) this.entries.delete(key)
  }

  ready(key: string, ticket: number): void {
    const entry: PreviewRevealEntry | undefined = this.entries.get(key)
    if (entry === undefined || entry.ticket !== ticket || entry.ready) return
    entry.ready = true
    this.schedule()
  }

  setStart(index: number): void {
    const start: number = Math.max(0, Math.min(index, Math.max(0, this.order.length - 1)))
    if (start > 0) this.beginBrowsing()
    if (start === this.start) return
    this.start = start
    this.schedule()
  }

  clear(): void {
    this.generation++
    this.posted = false
    this.context = undefined
    this.order = []
    this.entries.clear()
    this.revealed.clear()
    this.browsed = false
    this.start = 0
  }

  private schedule(): void {
    if (this.posted || this.context === undefined || this.order.length === 0) return
    const generation: number = this.generation
    this.posted = true
    this.context.postFrameCallback({ onFrame: () => {
      if (generation !== this.generation) return
      this.posted = false
      for (let index: number = this.start; index < this.order.length; index++) {
        const key: string = this.order[index]
        const entry: PreviewRevealEntry | undefined = this.entries.get(key)
        if (entry === undefined) break
        const immediate: boolean = this.browsed || this.revealed.has(key)
        // Initially, the prepared prefix fades together. Once browsing starts,
        // native summaries/media placeholders remain readable while optional
        // rich hosts prepare at rest; they must not hide an entire viewport.
        if (!entry.ready && !immediate) break
        if (!entry.released) {
          entry.released = true; this.revealed.add(key); entry.show(immediate)
        }
      }
    }, onIdle: () => {} })
  }
}
