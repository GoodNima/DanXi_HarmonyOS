import { http } from '@kit.NetworkKit'
import { SportsBooking } from '../model/SportsBooking'
import { SportsBookingRepository } from '../repository/SportsBookingRepository'
import { CampusCookies } from '../common/CampusCookies'
import { NetworkProxy } from '../common/NetworkProxy'
import { HttpUtil } from './HttpUtil'

interface BookingImageRecord { bytes: ArrayBuffer; at: number }

/** Venue photos use the booking download protocol, never a forum image URL.
 * Lazy rows share downloads; at most two transfers and 16 MiB are retained. */
export class BookingImageCache {
  private static records: Map<string, BookingImageRecord> = new Map()
  private static flights: Map<string, Promise<ArrayBuffer>> = new Map()
  private static slots: number = 0
  private static waiters: (() => void)[] = []
  static owner(): string { return new SportsBookingRepository().owner() }
  static read(token: string): Promise<ArrayBuffer> {
    if (!token || token.length > 4096) return Promise.reject(new Error('Invalid venue image token'))
    const owner = BookingImageCache.owner(), key = owner + '/' + token
    const cached = BookingImageCache.records.get(key)
    if (cached !== undefined && Date.now() - cached.at < 30 * 60000) {
      BookingImageCache.records.delete(key); BookingImageCache.records.set(key, cached)
      return Promise.resolve(cached.bytes)
    }
    const joined = BookingImageCache.flights.get(key); if (joined !== undefined) return joined
    const task = BookingImageCache.download(token, owner).then((bytes: ArrayBuffer): ArrayBuffer => {
      if (owner !== BookingImageCache.owner()) throw new Error('Venue image account changed')
      BookingImageCache.records.set(key, { bytes, at: Date.now() })
      let size: number = 0; for (const record of BookingImageCache.records.values()) size += record.bytes.byteLength
      while (size > 16 * 1024 * 1024 || BookingImageCache.records.size > 32) {
        const first: string | undefined = BookingImageCache.records.keys().next().value
        if (first === undefined) break
        size -= BookingImageCache.records.get(first)?.bytes.byteLength ?? 0; BookingImageCache.records.delete(first)
      }
      return bytes
    }).finally(() => { if (BookingImageCache.flights.get(key) === task) BookingImageCache.flights.delete(key) })
    BookingImageCache.flights.set(key, task); return task
  }
  private static async acquire(): Promise<void> {
    if (BookingImageCache.slots < 2) { BookingImageCache.slots++; return }
    await new Promise<void>(resolve => { BookingImageCache.waiters.push(resolve) })
  }
  private static release(): void {
    const next = BookingImageCache.waiters.shift(); if (next !== undefined) next(); else BookingImageCache.slots--
  }
  private static async download(token: string, owner: string): Promise<ArrayBuffer> {
    await BookingImageCache.acquire()
    const request = http.createHttp()
    try {
      if (owner !== BookingImageCache.owner()) throw new Error('Venue image account changed')
      await NetworkProxy.init()
      const url = SportsBooking.ORIGIN + '/reservation/api/file/down?token=' + encodeURIComponent(token) + '&view=1'
      const headers: Record<string, string> = {}
      headers['Cookie'] = await CampusCookies.read(url); headers['Referer'] = SportsBooking.TOPIC
      headers['Accept'] = 'image/*'; headers['User-Agent'] = HttpUtil.BROWSER_UA
      const options: http.HttpRequestOptions = { method: http.RequestMethod.GET, header: headers,
        expectDataType: http.HttpDataType.ARRAY_BUFFER, connectTimeout: 5000, readTimeout: 12000, maxLimit: 8 * 1024 * 1024 }
      const response = await request.request(url, NetworkProxy.apply(options))
      const responseHeaders = response.header as Record<string, string>
      const contentType = Object.keys(responseHeaders).find((key: string) => key.toLowerCase() === 'content-type')
      if (response.responseCode !== 200 || !contentType || !String(responseHeaders[contentType]).toLowerCase().startsWith('image/') || !(response.result instanceof ArrayBuffer)) throw new Error('Invalid venue image response')
      const bytes = response.result as ArrayBuffer
      if (bytes.byteLength === 0 || bytes.byteLength > 8 * 1024 * 1024) throw new Error('Invalid venue image size')
      return bytes
    } finally { request.destroy(); BookingImageCache.release() }
  }
}
