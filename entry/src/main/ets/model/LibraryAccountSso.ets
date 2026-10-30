import { url } from '@kit.ArkTS'
import { FduAuthPolicy } from './FduAuth'
import { CampusHtml } from './CampusHtml'

/** An ID result may return only to the reader callback named by this exact
 * redirect chain. This does not authorize campus credentials or business POSTs. */
export class LibraryAccountSso {
  method: string = 'GET'
  target: string = ''
  callback: string = ''
  fields: Record<string, string> = {}

  private static normalized(value: string, base: string = ''): string {
    if (!value || value.length > 8192 || /[\x00-\x20\x7f\\]/.test(value)) return ''
    try {
      const parsed = url.URL.parseURL(value, base || undefined)
      if (parsed.username || parsed.password || parsed.hash) return ''
      return parsed.toString()
    } catch (error) { return '' }
  }

  private static reader(value: string): boolean {
    return FduAuthPolicy.origin(value) === 'https://rwsjcas.fudan.edu.cn'
  }

  static callbackFor(entry: string, landing: string, hops: Record<string, string>[]): string {
    if (!LibraryAccountSso.reader(entry) || !FduAuthPolicy.isIdUrl(landing) || hops.length > 32) return ''
    const observed: string[] = []
    let current: string = entry
    for (const headers of hops) {
      if (!headers['location']) continue
      current = FduAuthPolicy.resolve(headers['location'], current)
      if (!current) return ''
      if (FduAuthPolicy.isIdUrl(current)) observed.push(current)
    }
    observed.push(landing)
    let callback: string = ''
    for (const location of observed) {
      const values = location.match(/[?&]service=([^&#]*)/gi) ?? []
      if (values.length > 1) return ''
      if (values.length === 0) continue
      let candidate: string = ''
      const parameter: string = values[0] ?? ''
      try { candidate = LibraryAccountSso.normalized(decodeURIComponent(parameter.substring(parameter.indexOf('=') + 1).replace(/\+/g, ' '))) }
      catch (error) { return '' }
      if (!LibraryAccountSso.reader(candidate) || (callback && callback !== candidate)) return ''
      callback = candidate
    }
    return callback
  }

  private static attributes(markup: string): Record<string, string> | null {
    const attributes: Record<string, string> = {}
    const names: Set<string> = new Set<string>()
    const pattern = /([^\s=<>\/]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g
    let match: RegExpExecArray | null = pattern.exec(markup)
    while (match !== null) {
      const name: string = match[1].toLowerCase()
      if (names.has(name) || /^(?:__proto__|prototype|constructor)$/.test(name)) return null
      names.add(name)
      attributes[name] = CampusHtml.decode(match[2] ?? match[3] ?? match[4] ?? '')
      match = pattern.exec(markup)
    }
    return attributes
  }

  static fromHtml(html: string, landing: string, callback: string): LibraryAccountSso | null {
    if (!FduAuthPolicy.isIdUrl(landing) || !LibraryAccountSso.reader(callback) || html.length > 1048576) return null
    const clean: string = html.replace(/<!--[\s\S]*?-->/g, '').replace(/<(?:script|style)\b[^>]*>[\s\S]*?<\/(?:script|style)\s*>/gi, '')
    const matches: string[] = []
    const forms: string[] = clean.match(/<form\b[^>]*>[\s\S]*?<\/form\s*>/gi) ?? []
    if (forms.length > 16) return null
    for (const form of forms) {
      const attributes = LibraryAccountSso.attributes(/^<form\b[^>]*>/i.exec(form)?.[0] ?? '')
      if (attributes?.['id'] === 'logon') matches.push(form)
    }
    if (matches.length !== 1) return null
    const form: string = matches[0]
    const attributes = LibraryAccountSso.attributes(/^<form\b[^>]*>/i.exec(form)?.[0] ?? '')
    if (attributes === null) return null
    const method: string = (attributes['method'] ?? 'GET').trim().toUpperCase()
    const action: string = LibraryAccountSso.normalized(attributes['action'] ?? '', landing)
    if (action !== callback || (method !== 'GET' && method !== 'POST') ||
      (method === 'POST' && attributes['enctype'] !== undefined && attributes['enctype'].toLowerCase() !== 'application/x-www-form-urlencoded') ||
      /<(?:textarea|select|button)\b[^>]*\bname\s*=/i.test(form)) return null
    const result = new LibraryAccountSso()
    result.method = method; result.target = action; result.callback = callback
    const names: Set<string> = new Set<string>()
    let bytes: number = 0
    for (const input of form.match(/<input\b[^>]*>/gi) ?? []) {
      const field = LibraryAccountSso.attributes(input)
      if (field === null || field['form'] !== undefined || /\sdisabled(?:\s|=|>)/i.test(input.replace(/"[^"]*"|'[^']*'/g, ''))) return null
      const type: string = (field['type'] ?? 'text').toLowerCase()
      if (type === 'password') return null
      const name: string = field['name'] ?? (field['id'] === 'ticket' ? 'ticket' : '')
      if (!name) continue
      const key: string = name.toLowerCase()
      const value: string = field['value'] ?? ''
      bytes += name.length + value.length
      if (names.has(key) || !/^[A-Za-z_][A-Za-z0-9_.-]{0,127}$/.test(name) ||
        /^(?:__proto__|prototype|constructor)$/.test(key) || /password|passwd|credential/i.test(name) ||
        /^(?:pass|pwd|username|user|loginname|idtoken1|idtoken2|studentid|verifycode|captcha|otp)$/i.test(key.replace(/[_.-]/g, '')) ||
        (method === 'POST' && type !== 'hidden') || names.size >= 64 || value.length > 16384 || bytes > 65536) return null
      try { encodeURIComponent(value) } catch (error) { return null }
      names.add(key); result.fields[name] = value
    }
    if (method === 'GET' ? !result.fields['ticket'] : !result.fields['code'] || !result.fields['state']) return null
    if (method === 'GET') {
      for (const name of Object.keys(result.fields)) result.target += (result.target.includes('?') ? '&' : '?') +
        encodeURIComponent(name) + '=' + encodeURIComponent(result.fields[name])
    }
    return result
  }
}
