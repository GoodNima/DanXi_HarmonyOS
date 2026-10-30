import { fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { BrowserLink } from '../common/BrowserLink'
import { ForumImageTransfer } from './ForumImageTransfer'

class ForumImageRecord {
  address: string = ''
  name: string = ''
  used: number = 0
  bytes: number = 0
}

class ForumImageFlight {
  key: string = ''
  address: string = ''
  path: string = ''
  consumers: number = 0
  settled: boolean = false
  transfer: ForumImageTransfer = new ForumImageTransfer()
  promise: Promise<string> = Promise.resolve('')
}

/** Reuse bytes already fetched by a floor thumbnail in the full-screen viewer.
 * Entries live in the application's cache directory, not shared storage.
 */
export class ForumImageCache {
  private static files: Map<string, string> = new Map<string, string>()
  private static sequence: number = 0
  private static prepared: Set<string> = new Set<string>()
  private static readonly LIMIT: number = 64
  private static readonly MAX_BYTES: number = 96 * 1024 * 1024
  private static readonly MAX_AGE: number = 7 * 24 * 60 * 60 * 1000
  private static records: Map<string, ForumImageRecord> = new Map<string, ForumImageRecord>()
  private static inFlight: Map<string, ForumImageFlight> = new Map<string, ForumImageFlight>()
  private static saveTimer: number = -1
  private flight: ForumImageFlight | null = null
  private rejectPending: (() => void) | null = null
  private cancelled: boolean = false

  static cached(source: string): string {
    const address: string = BrowserLink.normalize(source)
    const path: string = ForumImageCache.files.get(address) ?? ''
    if (!path) return ''
    try {
      if (fs.accessSync(path)) {
        ForumImageCache.files.delete(address)
        ForumImageCache.files.set(address, path)
        const record = ForumImageCache.records.get(address)
        if (record) record.used = Date.now()
        ForumImageCache.queueSave()
        return 'file://' + path
      }
    } catch (e) {}
    ForumImageCache.forget(address)
    return ''
  }

  /** Clear completed owned image bytes only. Active consumers and unrelated cache files remain intact. */
  static async clearCompleted(cacheDir: string): Promise<void> {
    ForumImageCache.restore(cacheDir)
    const paths: string[] = []
    for (const address of Array.from(ForumImageCache.files.keys())) {
      const path: string = ForumImageCache.files.get(address) ?? ''
      if (!path.startsWith(cacheDir + '/') || !/^danxi-image-\d+-\d+$/.test(path.substring(cacheDir.length + 1))) continue
      paths.push(path)
      ForumImageCache.files.delete(address)
      ForumImageCache.records.delete(address)
    }
    for (const path of paths) {
      try { await fs.unlink(path) } catch (e) {}
    }
    ForumImageCache.save()
  }

  static forget(source: string, expected: string = '', persist: boolean = true): void {
    const address: string = BrowserLink.normalize(source)
    const path: string = ForumImageCache.files.get(address) ?? ''
    if (expected && expected !== 'file://' + path) return
    ForumImageCache.files.delete(address)
    ForumImageCache.records.delete(address)
    if (path) fs.unlink(path).catch(() => {})
    if (persist) ForumImageCache.save()
  }

  private static prepare(cacheDir: string): void {
    if (ForumImageCache.prepared.has(cacheDir)) return
    ForumImageCache.prepared.add(cacheDir)
    const index: string = cacheDir + '/danxi-image-index.json'
    // Restore only validated names inside this cache directory. The index is
    // private to the app and never supplies arbitrary filesystem paths.
    try {
      if (fs.statSync(index).size <= 256 * 1024) {
        const rows = JSON.parse(fs.readTextSync(index)) as ForumImageRecord[]
        if (Array.isArray(rows) && rows.length <= ForumImageCache.LIMIT) {
          rows.sort((a: ForumImageRecord, b: ForumImageRecord): number => a.used - b.used)
          for (const row of rows) {
            if (!row || typeof row.address !== 'string' || BrowserLink.normalize(row.address) !== row.address ||
              !/^danxi-image-\d+-\d+$/.test(row.name) || !Number.isFinite(row.used) ||
              row.used > Date.now() + 60000 || Date.now() - row.used > ForumImageCache.MAX_AGE) continue
            const path: string = cacheDir + '/' + row.name
            let bytes: number = 0
            try { bytes = fs.statSync(path).size } catch (e) { continue }
            if (bytes <= 0 || bytes !== row.bytes) continue
            ForumImageCache.files.set(row.address, path)
            ForumImageCache.records.set(row.address, row)
          }
        }
      }
    } catch (e) {}
    try {
      for (const name of fs.listFileSync(cacheDir)) {
        const path: string = cacheDir + '/' + name
        if (/^danxi-image-\d+-\d+$/.test(name) && !Array.from(ForumImageCache.files.values()).includes(path)) {
          fs.unlink(path).catch(() => {})
        }
      }
    } catch (e) {}
    ForumImageCache.trim()
  }

  static restore(cacheDir: string): void { ForumImageCache.prepare(cacheDir) }

  private static queueSave(): void {
    if (ForumImageCache.saveTimer >= 0) return
    ForumImageCache.saveTimer = setTimeout(() => { ForumImageCache.saveTimer = -1; ForumImageCache.save() }, 500)
  }

  private static save(): void {
    if (ForumImageCache.saveTimer >= 0) {
      clearTimeout(ForumImageCache.saveTimer); ForumImageCache.saveTimer = -1
    }
    for (const directory of ForumImageCache.prepared) {
      const rows: ForumImageRecord[] = []
      for (const address of ForumImageCache.files.keys()) {
        const record = ForumImageCache.records.get(address)
        const path = ForumImageCache.files.get(address) ?? ''
        if (record && path === directory + '/' + record.name) rows.push(record)
      }
      const temporary: string = directory + '/danxi-image-index.tmp'
      try {
        const file = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC)
        try {
          const encoded: Uint8Array = new util.TextEncoder().encodeInto(JSON.stringify(rows))
          let offset: number = 0
          while (offset < encoded.byteLength) {
            const count: number = fs.writeSync(file.fd,
              encoded.buffer.slice(encoded.byteOffset + offset, encoded.byteOffset + encoded.byteLength))
            if (count <= 0) throw new Error('无法写入图片缓存索引')
            offset += count
          }
        } finally { fs.closeSync(file) }
        fs.renameSync(temporary, directory + '/danxi-image-index.json')
      } catch (e) { fs.unlink(temporary).catch(() => {}) }
    }
  }

  private static trim(): void {
    let bytes: number = 0
    for (const record of ForumImageCache.records.values()) bytes += record.bytes
    while (ForumImageCache.files.size > ForumImageCache.LIMIT || bytes > ForumImageCache.MAX_BYTES) {
      const oldest: string = Array.from(ForumImageCache.files.keys())[0]
      bytes -= ForumImageCache.records.get(oldest)?.bytes ?? 0
      ForumImageCache.forget(oldest, '', false)
    }
  }

  private static async fetch(flight: ForumImageFlight): Promise<string> {
    try {
      await flight.transfer.download(flight.address, flight.path)
      if (flight.consumers === 0) {
        try { await fs.unlink(flight.path) } catch (e) {}
        throw new Error('已取消下载')
      }
      const existing: string = ForumImageCache.cached(flight.address)
      if (existing) { try { await fs.unlink(flight.path) } catch (e) {}; return existing }
      const row = new ForumImageRecord()
      row.address = flight.address
      row.name = flight.path.substring(flight.path.lastIndexOf('/') + 1)
      row.used = Date.now()
      row.bytes = fs.statSync(flight.path).size
      // Never publish a URI which trim would immediately remove. Oversized
      // transfers remain owned by this flight and are removed by its catch.
      if (row.bytes <= 0 || row.bytes > ForumImageCache.MAX_BYTES) throw new Error('图片超出缓存大小限制')
      ForumImageCache.files.set(flight.address, flight.path)
      ForumImageCache.records.set(flight.address, row)
      ForumImageCache.trim()
      ForumImageCache.queueSave()
      return 'file://' + flight.path
    } catch (e) {
      try { await fs.unlink(flight.path) } catch (unlinkError) {}
      throw e as Error
    } finally {
      flight.settled = true
      if (ForumImageCache.inFlight.get(flight.key) === flight) ForumImageCache.inFlight.delete(flight.key)
    }
  }

  private release(): void {
    const flight = this.flight
    this.flight = null
    this.rejectPending = null
    if (flight === null) return
    flight.consumers--
    if (flight.consumers === 0 && !flight.settled) {
      if (ForumImageCache.inFlight.get(flight.key) === flight) ForumImageCache.inFlight.delete(flight.key)
      flight.transfer.cancel()
    }
  }

  async load(source: string, cacheDir: string): Promise<string> {
    if (this.cancelled) throw new Error('已取消下载')
    const address: string = BrowserLink.normalize(source)
    if (!address) throw new Error('图片地址无效')
    ForumImageCache.prepare(cacheDir)
    const existing: string = ForumImageCache.cached(address)
    if (existing) return existing
    const key: string = cacheDir + '\n' + address
    let flight = ForumImageCache.inFlight.get(key)
    if (flight === undefined) {
      flight = new ForumImageFlight()
      flight.key = key
      flight.address = address
      flight.path = cacheDir + '/danxi-image-' + Date.now() + '-' + (++ForumImageCache.sequence)
      flight.consumers = 1
      ForumImageCache.inFlight.set(key, flight)
      flight.promise = ForumImageCache.fetch(flight)
    } else flight.consumers++
    this.flight = flight
    const shared: ForumImageFlight = flight
    return new Promise<string>((resolve, reject) => {
      this.rejectPending = (): void => { reject(new Error('已取消下载')) }
      shared.promise.then((result: string) => {
        if (this.flight !== shared) return
        this.release()
        resolve(result)
      }).catch((e: Object) => {
        if (this.flight !== shared) return
        this.release()
        reject(e)
      })
    })
  }

  cancel(): void {
    this.cancelled = true
    this.rejectPending?.()
    this.release()
  }
}
