import { url } from '@kit.ArkTS'
import { FduAuthPolicy } from './FduAuth'
import { CasTicket } from './CasTicket'

class CampusSsoFormMarkup {
  html: string = ''
  logon: boolean = false
  method: string = 'GET'
  action: string = ''
  fields: Record<string, string> = {}
  count: number = 0
  valid: boolean = true
}

/** A bounded, parsed ID result form. This model never submits a request. */
export class CampusSsoForm {
  method: string = 'GET'
  targetUrl: string = ''
  fields: Record<string, string> = {}

  private static decode(value: string): string {
    return value.replace(/&#(x[0-9a-f]+|[0-9]+);/gi, (match: string, code: string): string => {
      const point = code.toLowerCase().startsWith('x') ? parseInt(code.substring(1), 16) : parseInt(code, 10)
      return point > 0 && point <= 0x10FFFF ? String.fromCodePoint(point) : match
    }).replace(/&quot;/gi, '"').replace(/&apos;|&#39;/gi, "'").replace(/&lt;/gi, '<')
      .replace(/&gt;/gi, '>').replace(/&amp;/gi, '&')
  }

  private static attributes(tag: string): Record<string, string> | null {
    const result: Record<string, string> = {}
    const seen: Set<string> = new Set<string>()
    const pattern = /([^\s=<>\/]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g
    let match: RegExpExecArray | null = pattern.exec(tag)
    while (match !== null) {
      const key: string = match[1].toLowerCase()
      if (seen.has(key) || /^(?:__proto__|prototype|constructor)$/.test(key)) return null
      seen.add(key)
      result[key] = CampusSsoForm.decode(match[2] ?? match[3] ?? match[4] ?? '')
      match = pattern.exec(tag)
    }
    return result
  }

  private static resolve(value: string, base: string): string {
    if (!value || value.length > 8192 || /[\x00-\x20\x7f\\]/.test(value)) return ''
    try { return url.URL.parseURL(value, base).toString() } catch (error) { return '' }
  }

  private static forms(html: string, base: string): CampusSsoFormMarkup[] {
    if (html.length > 1048576) return []
    const clean: string = html.replace(/<!--[\s\S]*?-->/g, '')
      .replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi, '')
      .replace(/<style\b[^>]*>[\s\S]*?<\/style\s*>/gi, '')
    const result: CampusSsoFormMarkup[] = []
    for (const form of clean.match(/<form\b[^>]*>[\s\S]*?<\/form\s*>/gi) ?? []) {
      if (result.length >= 16) return []
      const row = new CampusSsoFormMarkup()
      row.html = form
      const attrs = CampusSsoForm.attributes(/^<form\b[^>]*>/i.exec(form)?.[0] ?? '')
      if (attrs === null) { row.valid = false; result.push(row); continue }
      row.logon = attrs['id'] === 'logon'
      row.method = (attrs['method'] ?? 'GET').trim().toUpperCase()
      row.action = CampusSsoForm.resolve(attrs['action'] ?? '', base)
      if (!row.action || (row.method !== 'GET' && row.method !== 'POST') ||
        (row.method === 'POST' && attrs['enctype'] !== undefined &&
          attrs['enctype'].toLowerCase() !== 'application/x-www-form-urlencoded') ||
        /<(?:textarea|select|button)\b[^>]*\bname\s*=/i.test(form)) row.valid = false
      const seen: Set<string> = new Set<string>()
      let bytes: number = 0
      for (const input of form.match(/<input\b[^>]*>/gi) ?? []) {
        const field = CampusSsoForm.attributes(input)
        if (field === null) { row.valid = false; continue }
        const type: string = (field['type'] ?? 'text').toLowerCase()
        const attributeTokens: string = input.replace(/"[^"]*"|'[^']*'/g, '')
        if (type === 'password' || /\sdisabled(?:\s|=|>)/i.test(attributeTokens) || field['form'] !== undefined) row.valid = false
        const name: string = field['name'] ?? (field['id'] === 'ticket' ? 'ticket' : '')
        if (!name) continue
        row.count++
        const value: string = field['value'] ?? ''
        const key: string = name.toLowerCase()
        bytes += name.length + value.length
        if (seen.has(key) || !/^[A-Za-z_][A-Za-z0-9_.-]{0,127}$/.test(name) ||
          /^(?:__proto__|prototype|constructor)$/.test(key) ||
          /password|passwd|credential/i.test(name) ||
          /^(?:pass|pwd|username|user|loginname|idtoken1|idtoken2|studentid|verifycode|captcha|otp)$/i.test(name.replace(/[_.-]/g, '')) ||
          row.count > 64 || value.length > 16384 || bytes > 65536 ||
          (row.method === 'POST' && type !== 'hidden')) { row.valid = false; continue }
        try { encodeURIComponent(value) } catch (error) { row.valid = false; continue }
        seen.add(key)
        row.fields[name] = value
      }
      result.push(row)
    }
    return result
  }

  private static ecardService(value: string): boolean {
    return FduAuthPolicy.origin(value) === 'https://ecard.fudan.edu.cn' &&
      /^\/epay(?:\/(?:myepay\/index|j_spring_cas_security_check|wxpage\/fudan\/zfm\/qrcode)?)?$/.test(
        value.replace(/^https:\/\/[^/?#]+/i, '').split(/[?#]/)[0])
  }

  private static workflowCallback(value: string): boolean {
    return FduAuthPolicy.origin(value) === 'https://workflow1.fudan.edu.cn' &&
      value.replace(/^https:\/\/[^/?#]+/i, '').split(/[?#]/)[0] === '/site/login/cas-login'
  }

  private static observedWorkflow(base: string, service: string, entry: string, hops: Record<string, string>[]): boolean {
    if (!FduAuthPolicy.isIdUrl(base) || !CampusSsoForm.ecardService(service) ||
      !CampusSsoForm.ecardService(entry) || hops.length > 32) return false
    let current: string = entry
    let broker: boolean = false
    let idAfterBroker: boolean = false
    for (const headers of hops) {
      const location: string = headers['location'] ?? ''
      if (!location) continue
      current = CampusSsoForm.resolve(location, current)
      if (!current) return false
      if (CampusSsoForm.workflowCallback(current)) broker = true
      else if (broker && FduAuthPolicy.isIdUrl(current)) idAfterBroker = true
    }
    return broker && idAfterBroker && FduAuthPolicy.isIdUrl(current)
  }

  private static actionKind(row: CampusSsoFormMarkup, base: string, service: string, entry: string,
    hops: Record<string, string>[]): string {
    if (!row.action) return 'missing'
    if (FduAuthPolicy.isServiceUrl(row.action, service)) return 'service'
    return CampusSsoForm.workflowCallback(row.action) && CampusSsoForm.observedWorkflow(base, service, entry, hops) ?
      'observed-workflow' : 'untrusted'
  }

  private static getUrl(action: string, fields: Record<string, string>): string {
    const hash: number = action.indexOf('#')
    const fragment: string = hash < 0 ? '' : action.substring(hash)
    let target: string = hash < 0 ? action : action.substring(0, hash)
    for (const name of Object.keys(fields)) {
      const pair: string = encodeURIComponent(name) + '=' + encodeURIComponent(fields[name])
      if (name === 'ticket' && /[?&]ticket=/i.test(target)) target = target.replace(/([?&])ticket=[^&]*/i, '$1' + pair)
      else target += (target.includes('?') ? '&' : '?') + pair
    }
    return target + fragment
  }

  static fromHtml(html: string, base: string, service: string, entry: string,
    hops: Record<string, string>[]): CampusSsoForm | null {
    const forms = CampusSsoForm.forms(html, base)
    if (forms.filter(row => row.logon).length > 1) return null
    for (const row of forms) {
      if (!row.valid) continue
      const kind: string = CampusSsoForm.actionKind(row, base, service, entry, hops)
      const direct: boolean = kind === 'service' && row.method === 'GET' && !!row.fields['ticket'] &&
        CasTicket.fromHtml(row.html, base, service).length > 0
      const broker: boolean = kind === 'observed-workflow' && row.logon &&
        (row.method === 'GET' ? !!row.fields['ticket'] : row.method === 'POST' && !!row.fields['code'] && !!row.fields['state'])
      if (!direct && !broker) continue
      const result = new CampusSsoForm()
      result.method = row.method
      result.fields = row.fields
      result.targetUrl = row.method === 'GET' ? CampusSsoForm.getUrl(row.action, row.fields) : row.action
      return result
    }
    return null
  }

  /** Fixed classifications only: never expose URLs, input names or values. */
  static diagnostics(html: string, base: string, service: string, entry: string,
    hops: Record<string, string>[]): string {
    const forms = CampusSsoForm.forms(html, base)
    const row = forms.find(form => form.logon) ?? forms[0]
    return 'ssoForm; forms=' + String(forms.length) + '; logon=' + String(row?.logon ?? false) +
      '; method=' + (row === undefined ? 'missing' : row.method === 'GET' || row.method === 'POST' ? row.method : 'other') +
      '; ticket=' + String(!!row?.fields['ticket']) + '; code=' + String(!!row?.fields['code']) +
      '; state=' + String(!!row?.fields['state']) + '; fields=' + String(row?.count ?? 0) +
      '; valid=' + String(row?.valid ?? false) + '; action=' + (row === undefined ? 'missing' :
        CampusSsoForm.actionKind(row, base, service, entry, hops))
  }
}
