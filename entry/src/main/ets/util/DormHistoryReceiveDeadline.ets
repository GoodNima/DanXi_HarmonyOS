import { http } from '@kit.NetworkKit'

/** Response-header watchdog shares the query's full remaining budget.
 * A completed upload does not mean the backend can respond in five seconds.
 * Native readTimeout still bounds the entire connection and response transfer. */
export class DormHistoryReceiveTimeout extends Error {
  readonly code: number = 2300028
  constructor() { super('Operation timeout: electricity history response headers deadline') }
}

export class DormHistoryReceiveDeadline {
  readonly promise: Promise<http.HttpResponse>
  readonly budgetMs: number
  expired: boolean = false
  private headersReceived: boolean = false
  private waiting: boolean = false
  private timer: number = -1
  private rejectDeadline: ((reason: DormHistoryReceiveTimeout) => void) | null = null

  constructor(budgetMs: number = 15000) {
    this.budgetMs = budgetMs
    this.promise = new Promise<http.HttpResponse>((_resolve, reject) => { this.rejectDeadline = reject })
  }

  upload(sent: number, total: number): void {
    if (this.waiting || this.headersReceived || this.rejectDeadline === null || total <= 0 || sent < total) return
    this.waiting = true
    this.timer = setTimeout(() => {
      this.timer = -1
      this.expired = true
      if (this.rejectDeadline !== null) this.rejectDeadline(new DormHistoryReceiveTimeout())
    }, this.budgetMs)
  }

  headers(): void {
    this.headersReceived = true
    this.cancel()
  }

  cancel(): void {
    if (this.timer !== -1) clearTimeout(this.timer)
    this.timer = -1
    this.rejectDeadline = null
  }
}
