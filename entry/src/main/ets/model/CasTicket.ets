import { FduAuthPolicy } from './FduAuth'

/** Read the CAS auto-submit form without relying on quote style or attribute order. */
export class CasTicket {
  private static decode(value: string): string {
    return value.replace(/&#(x[0-9a-f]+|[0-9]+);/gi, (match: string, code: string): string => {
      const point = code.toLowerCase().startsWith('x') ? parseInt(code.substring(1), 16) : parseInt(code, 10)
      return point > 0 && point <= 0x10FFFF ? String.fromCodePoint(point) : match
    }).replace(/&quot;/gi, '"').replace(/&apos;|&#39;/gi, "'").replace(/&lt;/gi, '<')
      .replace(/&gt;/gi, '>').replace(/&amp;/gi, '&')
  }

  private static attributes(tag: string): Record<string, string> {
    const out: Record<string, string> = {}
    const pattern = /([^\s=<>\/]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g
    let match: RegExpExecArray | null = pattern.exec(tag)
    while (match !== null) {
      out[match[1].toLowerCase()] = CasTicket.decode(match[2] ?? match[3] ?? match[4] ?? '')
      match = pattern.exec(tag)
    }
    return out
  }

  static fromHtml(html: string, base: string, service: string): string {
    const forms = /<form\b[^>]*>[\s\S]*?<\/form\s*>/gi
    let form: RegExpExecArray | null = forms.exec(html)
    while (form !== null) {
      const opening = /^<form\b[^>]*>/i.exec(form[0])
      const action = opening === null ? '' : CasTicket.attributes(opening[0])['action'] ?? ''
      const inputs = /<input\b[^>]*>/gi
      let input: RegExpExecArray | null = inputs.exec(form[0])
      while (input !== null) {
        const attrs = CasTicket.attributes(input[0])
        if ((attrs['id'] === 'ticket' || attrs['name'] === 'ticket') && attrs['value'] && action) {
          const target = FduAuthPolicy.resolve(action, base)
          if (!FduAuthPolicy.isServiceUrl(target, service)) return ''
          const hashIndex = target.indexOf('#')
          const fragment = hashIndex >= 0 ? target.substring(hashIndex) : ''
          const clean = hashIndex >= 0 ? target.substring(0, hashIndex) : target
          const ticket = encodeURIComponent(attrs['value'])
          if (/[?&]ticket=/i.test(clean)) return clean.replace(/([?&])ticket=[^&]*/i, '$1ticket=' + ticket) + fragment
          return clean + (clean.includes('?') ? '&' : '?') + 'ticket=' + ticket + fragment
        }
        input = inputs.exec(form[0])
      }
      form = forms.exec(html)
    }
    return ''
  }

  static finalUrl(start: string, hops: Record<string, string>[]): string {
    let current = start
    for (const headers of hops) {
      if (headers['location']) current = FduAuthPolicy.resolve(headers['location'], current)
    }
    return current
  }
}
