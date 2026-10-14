/** Minimal HTML tree for the upstream's exact structural table selectors.
 * Scripts/styles are never executed. It accepts an omitted tbody, common in
 * server HTML, without searching unrelated tables for coincidental numbers. */
export class CampusHtmlNode {
  tag: string = ''
  attributes: Record<string, string> = {}
  children: CampusHtmlNode[] = []
  body: string = ''
  private orderedBody: string = ''
  private spanlessBody: string = ''
  appendText(value: string, insideSpan: boolean = false): void {
    this.orderedBody += value
    if (!insideSpan) this.spanlessBody += value
  }
  orderedText(): string { return CampusHtml.decode(this.orderedBody).replace(/\s+/g, ' ').trim() }
  /** Classroom course text follows iOS's select("span").remove(): keep font
   * fragments in document order, but do not turn span-only annotations into courses. */
  orderedTextWithoutSpans(): string { return CampusHtml.decode(this.spanlessBody).replace(/\s+/g, ' ').trim() }
  direct(tag: string): CampusHtmlNode[] { return this.children.filter(node => node.tag === tag) }
  private rawText(): string { return this.body + this.children.map(node => node.rawText()).join(' ') }
  text(): string { return CampusHtml.decode(this.rawText()).replace(/\s+/g, ' ').trim() }
  findId(id: string): CampusHtmlNode | undefined {
    if (this.attributes['id'] === id) return this
    for (const child of this.children) { const match = child.findId(id); if (match !== undefined) return match }
    return undefined
  }
  rows(): CampusHtmlNode[] {
    const rows: CampusHtmlNode[] = []
    for (const child of this.children) {
      if (child.tag === 'tr') rows.push(child)
      else if (['tbody', 'thead', 'tfoot'].includes(child.tag)) rows.push(...child.direct('tr'))
    }
    return rows
  }
}

export class CampusHtml {
  static decode(value: string): string {
    // One HTML decoding pass: &amp;quot; is the literal &quot;, not a quote.
    // Repeated decoding would corrupt the native QR credential payload.
    return value.replace(/&(nbsp|amp|lt|gt|quot|apos|#\d+|#x[0-9a-f]+);/gi, (all: string, entity: string): string => {
      const key = entity.toLowerCase()
      if (key === 'nbsp' || key === '#160') return ' '
      if (key === 'amp') return '&'
      if (key === 'lt') return '<'
      if (key === 'gt') return '>'
      if (key === 'quot') return '"'
      if (key === 'apos') return "'"
      const code = key.startsWith('#x') ? parseInt(key.slice(2), 16) : Number(key.slice(1))
      return Number.isSafeInteger(code) && code >= 0 && code <= 0x10FFFF ? String.fromCodePoint(code) : all
    })
  }
  static parse(html: string): CampusHtmlNode {
    const clean = html.replace(/<!--[^]*?-->/g, '').replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, '')
    const root = new CampusHtmlNode(); root.tag = 'root'
    const stack: CampusHtmlNode[] = [root]
    const tokens = /<[^>]+>|[^<]+/g
    let token = tokens.exec(clean)
    while (token !== null) {
      const value: string = token[0]
      if (value.startsWith('</')) {
        const closing = /^<\/\s*([\w-]+)/.exec(value)
        if (closing !== null) {
          for (let i: number = stack.length - 1; i > 0; i--) {
            if (stack[i].tag === closing[1].toLowerCase()) { stack.length = i; break }
          }
        }
      } else if (value.startsWith('<')) {
        const opening = /^<\s*([\w-]+)/.exec(value)
        if (opening !== null) {
          const node = new CampusHtmlNode(); node.tag = opening[1].toLowerCase()
          // ASP tables often omit </td> and </tr>. Match the browser/SwiftSoup
          // implied-end-tag rules within the nearest table, without flattening
          // the nested table used for the classroom name.
          if (['td', 'th', 'tr', 'tbody', 'thead', 'tfoot'].includes(node.tag)) {
            for (let i: number = stack.length - 1; i > 0; i--) {
              if (stack[i].tag === 'table') break
              const tag: string = stack[i].tag
              if ((['td', 'th'].includes(node.tag) && ['td', 'th'].includes(tag)) ||
                (node.tag === 'tr' && tag === 'tr') ||
                (['tbody', 'thead', 'tfoot'].includes(node.tag) && ['tbody', 'thead', 'tfoot'].includes(tag))) {
                stack.length = i; break
              }
            }
          }
          const pattern = /([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g
          let attribute = pattern.exec(value)
          while (attribute !== null) {
            node.attributes[attribute[1].toLowerCase()] = CampusHtml.decode(attribute[2] ?? attribute[3] ?? attribute[4] ?? '')
            attribute = pattern.exec(value)
          }
          stack[stack.length - 1].children.push(node)
          if (!['input', 'img', 'br', 'hr', 'meta', 'link', 'area', 'source', 'wbr'].includes(node.tag) && !value.endsWith('/>')) stack.push(node)
        }
      } else {
        stack[stack.length - 1].body += value
        const insideSpan: boolean = stack.some((node: CampusHtmlNode): boolean => node.tag === 'span')
        for (const node of stack) node.appendText(value, insideSpan)
      }
      token = tokens.exec(clean)
    }
    return root
  }
}
