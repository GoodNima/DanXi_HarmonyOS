import { ForumFloor, ForumHole } from './Forum'
import { ForumQuoteRepository } from './ForumQuoteRepository'

/** Resolved source data, before applying this reader's fold preference. */
export class ForumQuoteContent {
  floor: ForumFloor
  caution: boolean
  constructor(floor: ForumFloor, caution: boolean = false) {
    this.floor = floor
    this.caution = caution
  }

  /** A missing 0F body does not remove the containing thread or its replies. */
  static fromHole(hole: ForumHole, caution: boolean): ForumQuoteContent {
    if (hole.firstFloor !== null) return new ForumQuoteContent(hole.firstFloor, caution)
    const opening: ForumFloor = new ForumFloor()
    opening.holeId = hole.holeId; opening.deleted = true
    return new ForumQuoteContent(opening, caution)
  }

  static canNavigate(floor: ForumFloor | null): boolean {
    return floor !== null && Number.isSafeInteger(floor.holeId) && floor.holeId > 0
  }
}

class ForumQuoteEntry {
  content: ForumQuoteContent | null = null
  expiresAt: number = 0
  pending: Promise<ForumQuoteContent> | null = null
}

class ForumQuoteStore {
  scope: number = -1
  entries: Map<string, ForumQuoteEntry> = new Map<string, ForumQuoteEntry>()
}

/** Shared visible-reference reads. A session revision is an opaque local
 * account boundary, never a token. Failed reads are not cached or retried in
 * a loop; successful entries remain fresh briefly and the map stays bounded. */
export class ForumQuoteCache {
  private static readonly TTL_MS: number = 30000
  private static readonly MAX_ENTRIES: number = 128
  private static sources: WeakMap<ForumQuoteRepository, ForumQuoteStore> = new WeakMap<ForumQuoteRepository, ForumQuoteStore>()

  static load(repository: ForumQuoteRepository, scope: number, kind: string, id: number,
    loader: () => Promise<ForumQuoteContent>): Promise<ForumQuoteContent> {
    if (!Number.isSafeInteger(scope) || scope < 0 || !Number.isSafeInteger(id) || id <= 0 ||
      (kind !== 'floor' && kind !== 'hole')) return Promise.reject(new Error('Invalid quote identity'))
    if (scope !== repository.sessionRevision()) return Promise.reject(new Error('Obsolete quote account'))
    let store: ForumQuoteStore | undefined = ForumQuoteCache.sources.get(repository)
    if (store === undefined) {
      store = new ForumQuoteStore()
      ForumQuoteCache.sources.set(repository, store)
    }
    // Independent sources cannot share fixture/production data even when their
    // local revision numbers coincide. A weak key releases temporary sources.
    const current: ForumQuoteStore = store
    if (scope !== current.scope) {
      current.scope = scope
      current.entries.clear()
    }
    const key: string = kind + '/' + id
    const previous: ForumQuoteEntry | undefined = current.entries.get(key)
    if (previous?.pending) return previous.pending
    if (previous?.content && previous.expiresAt > Date.now()) return Promise.resolve(previous.content)
    const entry: ForumQuoteEntry = new ForumQuoteEntry()
    if (current.entries.size >= ForumQuoteCache.MAX_ENTRIES) {
      const keys: string[] = Array.from(current.entries.keys())
      const first: string | undefined = keys[0]
      if (first !== undefined) current.entries.delete(first)
    }
    current.entries.set(key, entry)
    const pending: Promise<ForumQuoteContent> = Promise.resolve().then((): Promise<ForumQuoteContent> => {
      if (scope !== repository.sessionRevision()) throw new Error('Obsolete quote account')
      return loader()
    }).then((content: ForumQuoteContent): ForumQuoteContent => {
      if (scope === repository.sessionRevision() && scope === current.scope && current.entries.get(key) === entry) {
        entry.content = content
        entry.expiresAt = Date.now() + ForumQuoteCache.TTL_MS
        entry.pending = null
      }
      return content
    }).catch((e: Object) => {
      if (scope === current.scope && current.entries.get(key) === entry) current.entries.delete(key)
      throw e as Error
    })
    entry.pending = pending
    return pending
  }
}
