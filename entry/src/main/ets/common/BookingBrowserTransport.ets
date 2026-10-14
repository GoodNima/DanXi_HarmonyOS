import { AppState } from './AppState'
import { CampusCookies } from './CampusCookies'
import { HttpError } from '../util/HttpUtil'

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
  static read(url: string, headers: Record<string, string>): Promise<string> {
    if (!BookingBrowserTransport.allowed(url)) return Promise.reject(new Error('Invalid booking browser read endpoint'))
    const owner: string = BookingBrowserTransport.owner(), lease: number = BookingBrowserTransport.lease
    const key: string = owner + '/' + url
    const joined = BookingBrowserTransport.flights.get(key); if (joined !== undefined) return joined
    const task = BookingBrowserTransport.queue.then(async (): Promise<string> => {
      const reader = BookingBrowserTransport.reader
      if (reader === undefined || lease !== BookingBrowserTransport.lease || owner !== BookingBrowserTransport.owner()) {
        throw new HttpError(-2, 412, '场馆预约需要完成官方网站的安全验证，请点击继续验证。', '')
      }
      const result: string = await reader(url, headers)
      if (owner !== BookingBrowserTransport.owner() || lease !== BookingBrowserTransport.lease) throw new Error('Booking account changed')
      await CampusCookies.persist(); return result
    }).finally(() => { if (BookingBrowserTransport.flights.get(key) === task) BookingBrowserTransport.flights.delete(key) })
    BookingBrowserTransport.flights.set(key, task); BookingBrowserTransport.queue = task.then(() => {}, () => {})
    return task
  }
}
