import { AppState } from './AppState'
import { CampusCookies } from './CampusCookies'

export type BookingBrowserRead = (url: string, headers: Record<string, string>) => Promise<string>
/** A narrow read-only bridge to the official site's ArkWeb safety check.
 * Never evaluate challenge JavaScript ourselves, replay a mutation, or expose
 * campus credentials to JavaScript. ArkWeb owns its shared HttpOnly cookie jar. */
export class BookingBrowserTransport {
  private static reader: BookingBrowserRead | undefined = undefined
  private static lease: number = 0
  private static queue: Promise<void> = Promise.resolve()
  private static flights: Map<string, Promise<string>> = new Map()
  static owner(): string { return AppState.getPerson().getStudentId() + '/' + CampusCookies.generation() + '/' + AppState.isLoggedIn() }
  static bind(reader: BookingBrowserRead): number { BookingBrowserTransport.reader = reader; return ++BookingBrowserTransport.lease }
  static unbind(lease: number): void { if (lease === BookingBrowserTransport.lease) { BookingBrowserTransport.reader = undefined; BookingBrowserTransport.lease++ } }
  static allowed(url: string): boolean {
    return /^https:\/\/booking\.fudan\.edu\.cn\/reservation\/(?:api\/topic\/resource-list|site\/resource\/(?:detail|calendar|reserve-info)|site\/user\/detail-mobile|site\/appointment\/appointment-list)(?:\?|$)/.test(url)
  }
  private static requireCurrent(owner: string, lease: number): void {
    if (owner !== BookingBrowserTransport.owner()) {
      const error = new Error('账户已切换，已取消原场馆查询。 Booking account changed')
      error.name = 'BookingAccountChangedError'
      throw error
    }
    if (lease !== BookingBrowserTransport.lease) {
      const error = new Error('场馆安全检查页面已关闭，请重新加载。 Booking browser read cancelled')
      error.name = 'BookingBrowserReadCancelledError'
      throw error
    }
  }
  static read(url: string, headers: Record<string, string>): Promise<string> {
    if (!BookingBrowserTransport.allowed(url)) return Promise.reject(new Error('Invalid booking browser read endpoint'))
    const owner: string = BookingBrowserTransport.owner(), lease: number = BookingBrowserTransport.lease
    const key: string = owner + '/' + url
    const joined = BookingBrowserTransport.flights.get(key); if (joined !== undefined) return joined
    const task = BookingBrowserTransport.queue.then(async (): Promise<string> => {
      const reader = BookingBrowserTransport.reader
      BookingBrowserTransport.requireCurrent(owner, lease)
      if (reader === undefined) {
        const error = new Error('场馆安全检查页面尚未就绪，请重新加载。 Booking browser not ready')
        error.name = 'BookingBrowserNotReadyError'
        throw error
      }
      const result: string = await reader(url, headers)
      BookingBrowserTransport.requireCurrent(owner, lease)
      await CampusCookies.persist()
      BookingBrowserTransport.requireCurrent(owner, lease)
      return result
    }).finally(() => { if (BookingBrowserTransport.flights.get(key) === task) BookingBrowserTransport.flights.delete(key) })
    BookingBrowserTransport.flights.set(key, task); BookingBrowserTransport.queue = task.then(() => {}, () => {})
    return task
  }
}
