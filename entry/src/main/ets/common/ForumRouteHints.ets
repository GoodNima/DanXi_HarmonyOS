import { connection } from '@kit.NetworkKit'
import { PreferencesUtil } from '../util/PreferencesUtil'
import { ForumRoute } from './ForumRoute'
import { NetworkProxy } from './NetworkProxy'

export class ForumRouteContext {
  networkId: number = -1
  proxyAddress: string = ''
  available: boolean = false
  generation: number = 0
}

interface StoredForumRoute {
  origin: string
  networkId: number
  proxyAddress: string
  direct: boolean
  checkedAt: number
}

class PendingForumRoute {
  origin: string = ''
  context: ForumRouteContext = new ForumRouteContext()
  direct: boolean | undefined = undefined
}

/** Only successful real GETs are remembered. A hint chooses which trusted
 * route to try first; it is neither a credential nor proof of a live session. */
export class ForumRouteHints {
  private static readonly KEY: string = 'forum_verified_routes_v1'
  private static readonly MAX_AGE: number = 30 * 60 * 1000
  private static rows: StoredForumRoute[] = []
  private static loaded: boolean = false
  private static loading: Promise<void> | null = null
  private static writes: Promise<void> = Promise.resolve()
  private static network: ForumRouteContext = new ForumRouteContext()
  private static contextAt: number = 0
  private static contextEpoch: number = 0
  private static contextFlight: Promise<ForumRouteContext> | null = null
  private static pending: PendingForumRoute[] = []
  private static saving: boolean = false

  static context(): ForumRouteContext {
    const proxy: string = NetworkProxy.active()
    if (proxy !== ForumRouteHints.network.proxyAddress) ForumRouteHints.invalidateContext()
    const age: number = Date.now() - ForumRouteHints.contextAt
    if (ForumRouteHints.contextAt <= 0 || age < 0 || age >= 1000) ForumRouteHints.refreshContext().catch(() => {})
    const result = new ForumRouteContext()
    result.networkId = ForumRouteHints.network.networkId
    result.available = ForumRouteHints.network.available
    result.proxyAddress = proxy
    result.generation = ForumRouteHints.contextEpoch
    return result
  }

  static invalidateContext(): void {
    ForumRouteHints.contextEpoch++; ForumRouteHints.contextAt = 0; ForumRouteHints.contextFlight = null
    ForumRouteHints.network = new ForumRouteContext()
    ForumRouteHints.network.proxyAddress = NetworkProxy.active()
  }

  /** Network metadata is optional. Never synchronously cross the native bridge
   * while a feed mounts images, or wait for it before starting a real GET. */
  private static refreshContext(): Promise<ForumRouteContext> {
    if (ForumRouteHints.contextFlight !== null) return ForumRouteHints.contextFlight
    const epoch: number = ForumRouteHints.contextEpoch
    const proxy: string = NetworkProxy.active()
    const task = ForumRouteHints.readContext(proxy).then((value: ForumRouteContext): ForumRouteContext => {
      if (epoch !== ForumRouteHints.contextEpoch || proxy !== NetworkProxy.active()) {
        const ignored = new ForumRouteContext(); ignored.proxyAddress = NetworkProxy.active()
        ignored.generation = ForumRouteHints.contextEpoch; return ignored
      }
      value.generation = epoch
      ForumRouteHints.network = value; ForumRouteHints.contextAt = Date.now()
      return value
    })
    ForumRouteHints.contextFlight = task
    task.finally(() => {
      if (ForumRouteHints.contextFlight === task) ForumRouteHints.contextFlight = null
    }).catch(() => {})
    return task
  }

  private static async readContext(proxy: string): Promise<ForumRouteContext> {
    const missing = new ForumRouteContext(); missing.proxyAddress = proxy
    let timer: number = -1
    try {
      const outcome = connection.getDefaultNet().then((handle: connection.NetHandle): ForumRouteContext => {
        const value = new ForumRouteContext(); value.proxyAddress = proxy
        value.networkId = handle.netId; value.available = Number.isInteger(handle.netId) && handle.netId > 0
        return value
      }).catch((): ForumRouteContext => missing)
      const deadline = new Promise<ForumRouteContext>((resolve) => { timer = setTimeout(() => resolve(missing), 1000) })
      return await Promise.race([outcome, deadline])
    } catch (e) { return missing }
    finally { if (timer >= 0) clearTimeout(timer) }
  }

  static async init(): Promise<void> {
    ForumRouteHints.context()
    if (ForumRouteHints.loaded) return
    const pending: Promise<void> = ForumRouteHints.loading ?? ForumRouteHints.restore()
    ForumRouteHints.loading = pending
    try { await pending; ForumRouteHints.loaded = true }
    finally { if (ForumRouteHints.loading === pending) ForumRouteHints.loading = null }
  }

  private static async restore(): Promise<void> {
    try {
      const text: string = await PreferencesUtil.getInstance().getString(ForumRouteHints.KEY, '')
      if (!text || text.length > 16384) return
      const rows = JSON.parse(text) as StoredForumRoute[]
      if (!Array.isArray(rows)) return
      const now: number = Date.now()
      ForumRouteHints.rows = rows.filter((row: StoredForumRoute): boolean => row !== null &&
        typeof row.origin === 'string' && ForumRouteHints.trusted(row.origin) &&
        Number.isInteger(row.networkId) && row.networkId > 0 && typeof row.proxyAddress === 'string' &&
        row.proxyAddress.length <= 512 && typeof row.direct === 'boolean' &&
        Number.isFinite(row.checkedAt) && now >= row.checkedAt && now - row.checkedAt < ForumRouteHints.MAX_AGE).slice(-8)
    } catch (e) { ForumRouteHints.rows = [] }
  }

  static async read(origin: string, context: ForumRouteContext): Promise<boolean | undefined> {
    if (!context.available || !ForumRouteHints.trusted(origin)) return undefined
    // Startup prewarms this metadata. A slow preference read must not become
    // another API gate: use the normal route until restoration has finished.
    if (!ForumRouteHints.loaded) {
      ForumRouteHints.init().catch(() => {})
      return undefined
    }
    if (!ForumRouteHints.current(context)) return undefined
    const found = ForumRouteHints.rows.find((row: StoredForumRoute): boolean => row.origin === origin &&
      row.networkId === context.networkId && row.proxyAddress === context.proxyAddress)
    const age: number = found === undefined ? -1 : Date.now() - found.checkedAt
    return found !== undefined && age >= 0 && age < ForumRouteHints.MAX_AGE ? found.direct : undefined
  }

  static remember(origin: string, context: ForumRouteContext, direct: boolean): void {
    ForumRouteHints.update(origin, context, direct)
  }

  static forget(origin: string, context: ForumRouteContext): void {
    ForumRouteHints.update(origin, context, undefined)
  }

  private static update(origin: string, context: ForumRouteContext, direct: boolean | undefined): void {
    if (!context.available || context.generation !== ForumRouteHints.contextEpoch ||
      context.proxyAddress !== NetworkProxy.active() || !ForumRouteHints.trusted(origin)) return
    const now: number = Date.now()
    const previous = ForumRouteHints.rows.find((row: StoredForumRoute): boolean => row.origin === origin &&
      row.networkId === context.networkId && row.proxyAddress === context.proxyAddress)
    const queued: boolean = ForumRouteHints.pending.some((row: PendingForumRoute): boolean => row.origin === origin &&
      row.context.networkId === context.networkId && row.context.proxyAddress === context.proxyAddress)
    // The common repeated-success path stays entirely in memory. It does not
    // create one metadata query/Promise/Preferences flush for every image.
    if (!queued && (direct === undefined && previous === undefined || previous !== undefined && direct === previous.direct &&
      now >= previous.checkedAt && now - previous.checkedAt < 60000)) return
    ForumRouteHints.pending = ForumRouteHints.pending.filter((row: PendingForumRoute): boolean =>
      !(row.origin === origin && row.context.networkId === context.networkId && row.context.proxyAddress === context.proxyAddress))
    const next = new PendingForumRoute(); next.origin = origin; next.context = context; next.direct = direct
    ForumRouteHints.pending.push(next); ForumRouteHints.pending = ForumRouteHints.pending.slice(-32)
    ForumRouteHints.scheduleSave()
  }

  private static scheduleSave(): void {
    if (ForumRouteHints.saving || ForumRouteHints.pending.length === 0) return
    ForumRouteHints.saving = true
    const task = Promise.resolve().then(async (): Promise<void> => {
      await ForumRouteHints.init()
      const pending = ForumRouteHints.pending; ForumRouteHints.pending = []
      // One asynchronous network validation and one serialization/flush for
      // the batch. Old-network results never become a new network's hint.
      const active = await ForumRouteHints.refreshContext()
      if (!active.available) return
      const now: number = Date.now()
      let changed: boolean = false
      for (const update of pending) {
        if (update.context.generation !== active.generation || active.generation !== ForumRouteHints.contextEpoch ||
          update.context.networkId !== active.networkId || update.context.proxyAddress !== active.proxyAddress) continue
        const previous = ForumRouteHints.rows.find((row: StoredForumRoute): boolean => row.origin === update.origin &&
          row.networkId === active.networkId && row.proxyAddress === active.proxyAddress)
        if (update.direct === undefined && previous === undefined || previous !== undefined && update.direct === previous.direct &&
          now >= previous.checkedAt && now - previous.checkedAt < 60000) continue
        ForumRouteHints.rows = ForumRouteHints.rows.filter((row: StoredForumRoute): boolean =>
          now >= row.checkedAt && now - row.checkedAt < ForumRouteHints.MAX_AGE &&
          !(row.origin === update.origin && row.networkId === active.networkId && row.proxyAddress === active.proxyAddress))
        if (update.direct !== undefined) {
          const row: StoredForumRoute = { origin: update.origin, networkId: active.networkId,
            proxyAddress: active.proxyAddress, direct: update.direct, checkedAt: now }
          ForumRouteHints.rows.push(row); ForumRouteHints.rows = ForumRouteHints.rows.slice(-8)
        }
        changed = true
      }
      if (changed) await PreferencesUtil.getInstance().putString(ForumRouteHints.KEY, JSON.stringify(ForumRouteHints.rows))
    }).catch(() => {}).then((): void => {
      ForumRouteHints.saving = false
      ForumRouteHints.scheduleSave()
    })
    ForumRouteHints.writes = task
  }

  private static current(context: ForumRouteContext): boolean {
    const active: ForumRouteContext = ForumRouteHints.context()
    return active.available && active.generation === context.generation &&
      active.networkId === context.networkId && active.proxyAddress === context.proxyAddress
  }

  private static trusted(origin: string): boolean {
    return /^https:\/\/[^/?#]+$/.test(origin) && ForumRoute.proxyUrl(origin) !== ''
  }
}
