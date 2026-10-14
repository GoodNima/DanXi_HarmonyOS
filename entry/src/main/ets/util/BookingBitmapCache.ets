import { image } from '@kit.ImageKit'
import { BookingImageCache } from './BookingImageCache'

interface VenueBitmapRecord { bitmap: image.PixelMap; bytes: number; at: number; users: number }
interface VenueImageFailure { at: number; error: Error }
export type VenueImageReader = (token: string) => Promise<ArrayBuffer>

export class VenueBitmapLease {
  bitmap: image.PixelMap
  private released: boolean = false
  private onRelease: () => void
  constructor(bitmap: image.PixelMap, onRelease: () => void) { this.bitmap = bitmap; this.onRelease = onRelease }
  release(): void { if (this.released) return; this.released = true; this.onRelease() }
}

/** The cache owns decoded PixelMaps; rows hold leases. Scrolling reuses the
 * same native image immediately, without repeating decoding or releasing a
 * bitmap still displayed by another row or the venue detail. */
export class BookingBitmapCache {
  private static records: Map<string, VenueBitmapRecord> = new Map()
  private static flights: Map<string, Promise<VenueBitmapRecord>> = new Map()
  private static failures: Map<string, VenueImageFailure> = new Map()
  private static claims: Map<string, number> = new Map()
  static retryFailures(): void { BookingBitmapCache.failures.clear() }
  static identity(token: string, large: boolean = false): string {
    return BookingImageCache.owner() + (large ? '/detail/' : '/list/') + token
  }
  static retain(token: string, large: boolean = false): VenueBitmapLease | undefined {
    if (!token) return undefined
    const key: string = BookingBitmapCache.identity(token, large)
    const record = BookingBitmapCache.records.get(key)
    if (record === undefined) return undefined
    if (record.users === 0 && Date.now() - record.at > 30 * 60000) {
      BookingBitmapCache.records.delete(key); record.bitmap.release().catch(() => {}); return undefined
    }
    return BookingBitmapCache.lease(key, record)
  }
  private static lease(key: string, record: VenueBitmapRecord): VenueBitmapLease {
    record.users++; record.at = Date.now()
    BookingBitmapCache.records.delete(key); BookingBitmapCache.records.set(key, record)
    return new VenueBitmapLease(record.bitmap, () => { record.users--; BookingBitmapCache.trim() })
  }
  static async acquire(token: string, large: boolean = false,
    reader: VenueImageReader = (value: string): Promise<ArrayBuffer> => BookingImageCache.read(value)): Promise<VenueBitmapLease> {
    const owner: string = BookingImageCache.owner(), key: string = BookingBitmapCache.identity(token, large)
    const retained = BookingBitmapCache.retain(token, large); if (retained !== undefined) return retained
    const failure = BookingBitmapCache.failures.get(key)
    if (failure !== undefined && Date.now() - failure.at < 30000) throw failure.error
    // Protect decodes awaiting their leases as well as images already on screen.
    BookingBitmapCache.claims.set(key, (BookingBitmapCache.claims.get(key) ?? 0) + 1)
    try {
    let task: Promise<VenueBitmapRecord> | undefined = BookingBitmapCache.flights.get(key)
    if (task === undefined) {
      task = BookingBitmapCache.decode(token, owner, large, reader).then((record: VenueBitmapRecord): VenueBitmapRecord => {
        BookingBitmapCache.records.set(key, record); BookingBitmapCache.failures.delete(key)
        BookingBitmapCache.trim(key); return record
      }).catch((error: Error): VenueBitmapRecord => {
        BookingBitmapCache.failures.set(key, { at: Date.now(), error: error })
        while (BookingBitmapCache.failures.size > 64) {
          const first: string | undefined = BookingBitmapCache.failures.keys().next().value
          if (first !== undefined) BookingBitmapCache.failures.delete(first)
        }
        throw error
      }).finally(() => { if (BookingBitmapCache.flights.get(key) === task) BookingBitmapCache.flights.delete(key) })
      BookingBitmapCache.flights.set(key, task)
    }
    const record = await task
    if (owner !== BookingImageCache.owner()) throw new Error('Venue image account changed')
    return BookingBitmapCache.lease(key, record)
    } finally {
      const remaining: number = (BookingBitmapCache.claims.get(key) ?? 1) - 1
      if (remaining > 0) BookingBitmapCache.claims.set(key, remaining)
      else BookingBitmapCache.claims.delete(key)
      BookingBitmapCache.trim()
    }
  }
  private static async decode(token: string, owner: string, large: boolean, reader: VenueImageReader): Promise<VenueBitmapRecord> {
    let source: image.ImageSource | undefined = undefined
    try {
      const bytes = await reader(token)
      if (owner !== BookingImageCache.owner()) throw new Error('Venue image account changed')
      source = image.createImageSource(bytes)
      const info = await source.getImageInfo()
      if (info.size.width < 1 || info.size.height < 1 || info.size.width * info.size.height > 100000000) throw new Error('Invalid venue image dimensions')
      // A 96 × 64 vp list photo needs a thumbnail, not a detail-sized bitmap.
      // Keep a separate larger decode for the detail, sharing the byte cache.
      const ratio: number = Math.min(1, (large ? 960 : 384) / info.size.width, (large ? 640 : 256) / info.size.height)
      const width: number = Math.max(1, Math.round(info.size.width * ratio)), height: number = Math.max(1, Math.round(info.size.height * ratio))
      const bitmap = await source.createPixelMap({ desiredSize: { width: width, height: height } })
      if (owner !== BookingImageCache.owner()) { await bitmap.release(); throw new Error('Venue image account changed') }
      return { bitmap: bitmap, bytes: width * height * 4, at: Date.now(), users: 0 }
    } finally { if (source !== undefined) await source.release().catch(() => {}) }
  }
  private static trim(protectedKey: string = ''): void {
    let size: number = 0; for (const record of BookingBitmapCache.records.values()) size += record.bytes
    const owner: string = BookingImageCache.owner() + '/'
    for (const key of BookingBitmapCache.records.keys()) {
      const record = BookingBitmapCache.records.get(key)
      if (record === undefined || record.users > 0 || BookingBitmapCache.claims.has(key) || key === protectedKey) continue
      if (size > 32 * 1024 * 1024 || BookingBitmapCache.records.size > 96 || !key.startsWith(owner) || Date.now() - record.at > 30 * 60000) {
        BookingBitmapCache.records.delete(key); size -= record.bytes; record.bitmap.release().catch(() => {})
      }
    }
  }
}
