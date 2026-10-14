import { connection, http } from '@kit.NetworkKit'
import { webview } from '@kit.ArkWeb'
import { PreferencesUtil } from '../util/PreferencesUtil'

export class ProxyAddress {
  host: string
  port: number
  address: string
  constructor(host: string, port: number) {
    this.host = host; this.port = port
    this.address = (host.includes(':') ? '[' + host + ']' : host) + ':' + port
  }
}

/** One explicit HTTP proxy for native requests and in-app authentication Webs.
 * Changing it never clears cookies, credentials or the independent WebVPN preference. */
export class NetworkProxy {
  static readonly KEY_ACTIVE: string = 'network_http_proxy'
  static readonly KEY_SAVED: string = 'network_saved_proxies'
  private static loaded: boolean = false
  private static loading: Promise<void> | undefined = undefined
  private static writes: Promise<void> = Promise.resolve()
  private static currentProxy: string = ''

  static parse(value: string): ProxyAddress | null {
    const text = value.trim().replace(/^http:\/\//i, '').replace(/\/$/, '')
    const match = /^(?:\[([0-9a-fA-F:]+)\]|([a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?)):(\d{1,5})$/.exec(text)
    if (match === null) return null
    const host = (match[1] || match[2]).toLowerCase()
    const port = Number(match[3])
    if (!Number.isInteger(port) || port < 1 || port > 65535 || host.includes('..') ||
      (match[1] !== undefined && !host.includes(':'))) return null
    return new ProxyAddress(host, port)
  }

  static active(): string { return NetworkProxy.currentProxy }
  static saved(json: string = AppStorage.get<string>(NetworkProxy.KEY_SAVED) ?? '[]'): string[] {
    try {
      const values = JSON.parse(json) as string[]
      const result: string[] = []
      if (!Array.isArray(values)) return result
      for (const value of values) {
        if (typeof value !== 'string') continue
        const parsed = NetworkProxy.parse(value)
        if (parsed !== null && !result.includes(parsed.address)) result.push(parsed.address)
      }
      return result.slice(0, 32)
    } catch (e) { return [] }
  }

  static async init(): Promise<void> {
    if (NetworkProxy.loaded) return
    if (NetworkProxy.loading !== undefined) return NetworkProxy.loading
    NetworkProxy.loading = NetworkProxy.restore()
    try { await NetworkProxy.loading; NetworkProxy.loaded = true }
    finally { NetworkProxy.loading = undefined }
  }
  private static async restore(): Promise<void> {
    const prefs = PreferencesUtil.getInstance()
    AppStorage.setOrCreate<string>(NetworkProxy.KEY_SAVED, await prefs.getString(NetworkProxy.KEY_SAVED, '[]'))
    const active = NetworkProxy.parse(await prefs.getString(NetworkProxy.KEY_ACTIVE, ''))
    NetworkProxy.currentProxy = active?.address ?? ''
    AppStorage.setOrCreate<string>(NetworkProxy.KEY_ACTIVE, NetworkProxy.currentProxy)
    if (active !== null) {
      try { await NetworkProxy.web(active.address) }
      catch (e) { AppStorage.setOrCreate<string>('network_proxy_error', String(e)) }
    }
  }
  private static async web(address: string): Promise<void> {
    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => { reject(new Error('WebProxy configuration timeout')) }, 3000)
      const done = (): void => { clearTimeout(timeout); resolve() }
      try {
        if (!address) webview.ProxyController.removeProxyOverride(done)
        else {
          const config = new webview.ProxyConfig()
          config.insertProxyRule('http://' + address)
          webview.ProxyController.applyProxyOverride(config, done)
        }
      } catch (e) { clearTimeout(timeout); reject(e as Error) }
    })
  }
  private static enqueue(action: () => Promise<void>): Promise<void> {
    const task = NetworkProxy.writes.then(action, action)
    NetworkProxy.writes = task.catch(() => {})
    return task
  }
  static async select(value: string): Promise<void> {
    await NetworkProxy.init()
    const parsed = value ? NetworkProxy.parse(value) : null
    if (value && parsed === null) throw new Error('Invalid HTTP proxy address')
    const address = parsed?.address ?? ''
    await NetworkProxy.enqueue(() => NetworkProxy.commit(address))
  }
  private static async commit(address: string): Promise<void> {
    const previous = NetworkProxy.active()
    await NetworkProxy.web(address)
    try { await PreferencesUtil.getInstance().putString(NetworkProxy.KEY_ACTIVE, address) }
    catch (e) { await NetworkProxy.web(previous); throw e as Error }
    NetworkProxy.currentProxy = address
    AppStorage.setOrCreate<string>(NetworkProxy.KEY_ACTIVE, address)
    AppStorage.setOrCreate<string>('network_proxy_error', '')
  }
  static async add(value: string): Promise<void> {
    await NetworkProxy.init()
    const parsed = NetworkProxy.parse(value)
    if (parsed === null) throw new Error('Invalid HTTP proxy address')
    await NetworkProxy.enqueue(async () => {
      const saved = NetworkProxy.saved()
      if (saved.includes(parsed.address)) throw new Error('Proxy already exists')
      if (saved.length >= 32) throw new Error('Proxy address limit reached (32)')
      saved.push(parsed.address)
      const json = JSON.stringify(saved)
      await PreferencesUtil.getInstance().putString(NetworkProxy.KEY_SAVED, json)
      AppStorage.setOrCreate<string>(NetworkProxy.KEY_SAVED, json)
    })
  }
  static async remove(address: string): Promise<void> {
    await NetworkProxy.init()
    await NetworkProxy.enqueue(async () => {
      if (NetworkProxy.active() === address) await NetworkProxy.commit('')
      const json = JSON.stringify(NetworkProxy.saved().filter((row: string) => row !== address))
      await PreferencesUtil.getInstance().putString(NetworkProxy.KEY_SAVED, json)
      AppStorage.setOrCreate<string>(NetworkProxy.KEY_SAVED, json)
    })
  }
  static apply(options: http.HttpRequestOptions): http.HttpRequestOptions {
    if (!NetworkProxy.loaded && !NetworkProxy.currentProxy) return options
    const parsed = NetworkProxy.parse(NetworkProxy.active())
    if (parsed === null) options.usingProxy = false
    else {
      const proxy: connection.HttpProxy = { host: parsed.host, port: parsed.port, exclusionList: [] }
      options.usingProxy = proxy
    }
    return options
  }
}
