export class ForumContentPart {
  kind: string
  text: string
  source: string
  runs: ForumContentPart[] = []
  constructor(kind: string, text: string, source: string = '') {
    this.kind = kind; this.text = text; this.source = source
  }
}

/** Parse image/sticker Markdown as data; never execute post HTML or JavaScript. */
export class ForumContentParser {
  /** References/media already occupy their own block. Separator-only text
   * must not become a second paragraph layout between these blocks. Keep
   * internal paragraph breaks and code indentation intact. */
  static layoutParts(content: string): ForumContentPart[] {
    const result: ForumContentPart[] = []
    for (const part of ForumContentParser.parse(content)) {
      if (part.kind !== 'text') { result.push(part); continue }
      if (part.text.trim().length === 0) continue
      const text: string = part.text.replace(/^(?:[ \t]*\r?\n)+|(?:\r?\n[ \t]*)+$/g, '')
      result.push(new ForumContentPart('text', text, part.source))
    }
    return result
  }
  static displayParts(content: string): ForumContentPart[] {
    const result: ForumContentPart[] = []
    let runs: ForumContentPart[] = []
    const flush: () => void = (): void => {
      if (runs.length === 0) return
      if (runs.some((part: ForumContentPart) => part.kind === 'sticker')) {
        const first: ForumContentPart = runs[0]
        const last: ForumContentPart = runs[runs.length - 1]
        if (first.kind === 'text') first.text = first.text.replace(/^(?:[ \t]*\r?\n)+/g, '')
        if (last.kind === 'text') last.text = last.text.replace(/(?:\r?\n[ \t]*)+$/g, '')
        const group: ForumContentPart = new ForumContentPart('inline', runs.map((part: ForumContentPart) =>
          part.kind === 'sticker' ? '![' + part.text + '](' + part.source + ')' : part.text).join(''))
        group.runs = runs
        result.push(group)
      } else {
        for (const part of runs) {
          if (part.text.trim().length > 0) result.push(new ForumContentPart('text',
            part.text.replace(/^(?:[ \t]*\r?\n)+|(?:\r?\n[ \t]*)+$/g, '')))
        }
      }
      runs = []
    }
    for (const part of ForumContentParser.parse(content)) {
      if (part.kind === 'text' || part.kind === 'sticker') runs.push(part)
      else { flush(); result.push(part) }
    }
    flush()
    return result
  }

  /** Bound each native text layout without discarding characters or newlines. */
  static textBlocks(content: string): string[] {
    const blocks: string[] = []
    let start: number = 0
    while (start < content.length) {
      let end: number = Math.min(start + 1200, content.length)
      if (end < content.length) {
        const newline: number = content.lastIndexOf('\n', end)
        if (newline > start + 600) end = newline + 1
        const code: number = content.charCodeAt(end - 1)
        if (code >= 0xD800 && code <= 0xDBFF) end--
      }
      blocks.push(content.substring(start, end))
      start = end
    }
    return blocks
  }
  static parse(content: string): ForumContentPart[] {
    const parts: ForumContentPart[] = []
    // Consume code and Markdown links before mentions, so code/URL fragments
    // do not turn into unexpected authenticated requests.
    const pattern = /```[\s\S]*?```|~~~[\s\S]*?~~~|(?:^|\n)(?: {4}|\t)[^\n]*(?:\n(?: {4}|\t)[^\n]*)*|``[^\n]*?``|`[^`\n]*`|\\#{1,2}\d+|\$\$[\s\S]+?\$\$|\$[^$\n]+?\$|!\[([^\]]*)\]\(\s*(<[^>]+>|[^\s)]+)(?:\s+["'][^"']*["'])?\s*\)|<img\b[^>]*>|<[^>]+>|\[[^\]]*\]\([^)]*\)|https?:\/\/[^\s<>]+|(#{1,2})([0-9]+)/gi
    let offset: number = 0
    let match: RegExpExecArray | null = pattern.exec(content)
    while (match !== null) {
      if (match.index > offset) parts.push(new ForumContentPart('text', content.substring(offset, match.index)))
      if (match[3] !== undefined) {
        const id: number = Number(match[4])
        if (Number.isSafeInteger(id) && id > 0) {
          parts.push(new ForumContentPart(match[3] === '##' ? 'floor' : 'hole', match[0], String(id)))
        } else parts.push(new ForumContentPart('text', match[0]))
        offset = match.index + match[0].length
        match = pattern.exec(content)
        continue
      }
      if (!match[0].startsWith('![') && !/^<img\b/i.test(match[0])) {
        parts.push(new ForumContentPart('text', match[0]))
        offset = match.index + match[0].length
        match = pattern.exec(content)
        continue
      }
      const htmlSrc = /\bsrc\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))/i.exec(match[0])
      let source: string = match[2] ?? (htmlSrc ? htmlSrc[1] ?? htmlSrc[2] ?? htmlSrc[3] : '')
      source = source.replace(/^<|>$/g, '').replace(/&amp;/g, '&').replace(/^danxi_/, 'dx_')
      if (/^dx_[a-z0-9_]+$/i.test(source)) parts.push(new ForumContentPart('sticker', match[1] || '表情', source))
      else if (/^https?:\/\/[^\s<>]+$/i.test(source)) parts.push(new ForumContentPart('image', match[1] || '图片', source))
      else parts.push(new ForumContentPart('text', '[' + (match[1] || '无法显示的图片') + ']'))
      offset = match.index + match[0].length
      match = pattern.exec(content)
    }
    if (offset < content.length) parts.push(new ForumContentPart('text', content.substring(offset)))
    const merged: ForumContentPart[] = []
    for (const part of parts) {
      const previous = merged.length > 0 ? merged[merged.length - 1] : undefined
      if (part.kind === 'text' && previous?.kind === 'text') previous.text += part.text
      else merged.push(part)
    }
    return merged
  }

  static needsRich(content: string): boolean {
    // A URL is data, not Markdown decoration. In particular underscores,
    // query strings and fragment IDs inside it must not start an ArkWeb host.
    const prose: string = ForumContentParser.nativeLinks(content).map((part: ForumContentPart): string =>
      part.kind === 'link' ? (part.text === part.source ? '' : part.text) : part.text).join('')
    return /\$[^$]|[`*_~]|^\s*(?:#{1,6}\s|>|[-+]\s|\d+\.\s)|^(?: {4}|\t)\S|\\[!#*_`]|\[[^\]]*\]\(|<audit>|\|.*\|/m.test(prose)
  }

  /** Plain public links remain native text; complex Markdown is still rich. */
  static nativeLinks(content: string): ForumContentPart[] {
    const result: ForumContentPart[] = []
    const pattern = /```[\s\S]*?```|~~~[\s\S]*?~~~|``[^\n]*?``|`[^`\n]*`|\$\$[\s\S]+?\$\$|\$[^$\n]+?\$|\[([^\]\n]+)\]\(\s*(https?:\/\/[^\s()]+)(?:\s+["'][^"'\n]*["'])?\s*\)|https?:\/\/[^\s<>\u3000，。！？；：、…]+/gi
    let offset: number = 0
    let match: RegExpExecArray | null = pattern.exec(content)
    while (match !== null) {
      if (match.index > offset) result.push(new ForumContentPart('text', content.substring(offset, match.index)))
      if (!match[2] && !/^https?:\/\//i.test(match[0])) {
        result.push(new ForumContentPart('text', match[0]))
        offset = match.index + match[0].length
        match = pattern.exec(content)
        continue
      }
      const raw: string = match[2] || match[0]
      const address: string = match[2] ? raw : ForumContentParser.linkAddress(raw)
      const label: string = match[1] || address
      // Keep credential-bearing addresses readable, without offering a link
      // that BrowserLink would reject on click.
      if (address && !/^https?:\/\/[^/?#]*@/i.test(address)) {
        result.push(new ForumContentPart('link', label, address))
        if (!match[2] && address.length < raw.length) result.push(new ForumContentPart('text', raw.substring(address.length)))
      } else result.push(new ForumContentPart('text', match[0]))
      offset = match.index + match[0].length
      match = pattern.exec(content)
    }
    if (offset < content.length) result.push(new ForumContentPart('text', content.substring(offset)))
    return result
  }

  private static linkAddress(value: string): string {
    let address: string = value.replace(/[.,!?;:，。！？；：、。\u201d\u2019"']+$/g, '')
    const pairs: string[][] = [['(', ')'], ['[', ']'], ['（', '）'], ['【', '】'], ['《', '》'], ['「', '」'], ['『', '』']]
    let changed: boolean = true
    while (changed && address.length > 0) {
      changed = false
      for (const pair of pairs) {
        if (address.endsWith(pair[1]) && address.split(pair[1]).length > address.split(pair[0]).length) {
          address = address.substring(0, address.length - 1); changed = true
        }
      }
    }
    return address
  }

  /** Preserve an entire URL target even when its visible text crosses the
   * bounded native paragraphs used for very long floors. */
  static nativeBlocks(content: string): ForumContentPart[][] {
    const runs: ForumContentPart[] = ForumContentParser.nativeLinks(content)
    const blocks: string[] = ForumContentParser.textBlocks(runs.map((run: ForumContentPart): string => run.text).join(''))
    const result: ForumContentPart[][] = []
    let start: number = 0
    for (const block of blocks) {
      const end: number = start + block.length
      const row: ForumContentPart[] = []
      let offset: number = 0
      for (const run of runs) {
        const last: number = offset + run.text.length
        if (last > start && offset < end) row.push(new ForumContentPart(run.kind,
          run.text.substring(Math.max(0, start - offset), Math.min(run.text.length, end - offset)), run.source))
        offset = last
        if (offset >= end) break
      }
      result.push(row); start = end
    }
    return result
  }

  static summary(content: string, includeReferences: boolean = true): string {
    return ForumContentParser.parse(content).map((part: ForumContentPart) => {
      if (part.kind === 'image') return '[图片]'
      if (part.kind === 'sticker') return '[表情]'
      if (part.kind === 'floor' || part.kind === 'hole') return includeReferences ? '[引用 ' + part.text + ']' : ''
      return part.text.replace(/\$\$([\s\S]+?)\$\$|\$([^$\n]+?)\$/g, (value: string, display: string, inline: string): string => {
        return MathPlainText.render(display || inline)
      }).replace(/(?:```|~~~)[^\n]*\n([\s\S]*?)(?:```|~~~)/g, '$1')
        .replace(/`+([^`]+)`+/g, '$1').replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
        .replace(/^\s{0,3}#{1,6}\s+/gm, '').replace(/\*\*([^*]+)\*\*|__([^_]+)__/g, '$1$2')
        .replace(/\*([^*]+)\*|_([^_]+)_|~~([^~]+)~~/g, '$1$2$3')
        .replace(/<\/?audit>/g, '').replace(/\\([!#*_`\\])/g, '$1')
    }).join('').trim()
  }
}

/** Plain accessible/copy text for common TeX, without exposing font commands. */
class MathPlainText {
  private source: string
  private offset: number = 0
  constructor(source: string) { this.source = source }
  static render(source: string): string { return new MathPlainText(source).read(0) }
  private group(depth: number): string {
    while (this.source[this.offset] === ' ') this.offset++
    if (this.source[this.offset] !== '{') return ''
    this.offset++
    return this.read(depth + 1)
  }
  private read(depth: number): string {
    if (depth > 32) return ''
    let result: string = ''
    const symbols: Record<string, string> = { 'alpha': 'α', 'beta': 'β', 'gamma': 'γ', 'delta': 'δ', 'theta': 'θ', 'lambda': 'λ',
      'pi': 'π', 'sigma': 'σ', 'omega': 'ω', 'sum': '∑', 'prod': '∏', 'int': '∫', 'infty': '∞', 'times': '×', 'cdot': '·',
      'leq': '≤', 'geq': '≥', 'neq': '≠', 'pm': '±', 'quad': ' ', 'qquad': ' ', '\\': '\n' }
    while (this.offset < this.source.length) {
      const char: string = this.source[this.offset++]
      if (char === '}') return result
      if (char === '{') { result += this.read(depth + 1); continue }
      if (char !== '\\') { result += char; continue }
      let command: string = ''
      while (this.offset < this.source.length && /[a-zA-Z]/.test(this.source[this.offset])) command += this.source[this.offset++]
      if (!command) { result += this.source[this.offset++] ?? ''; continue }
      if (command === 'textcolor' || command === 'color') { this.group(depth); if (command === 'textcolor') result += this.group(depth); continue }
      if (['mathbf', 'mathit', 'mathrm', 'mathsf', 'mathtt', 'mathcal', 'mathbb', 'mathnormal', 'boldsymbol',
        'text', 'textbf', 'textit', 'textrm', 'textsf', 'texttt', 'emph', 'operatorname'].includes(command)) {
        result += this.group(depth); continue
      }
      // These declarations affect typography, not the accessible quote text.
      if (['tiny', 'scriptsize', 'footnotesize', 'small', 'normalsize', 'large', 'Large', 'LARGE', 'huge', 'Huge',
        'displaystyle', 'textstyle', 'scriptstyle', 'scriptscriptstyle', 'bf', 'it', 'rm', 'sf', 'tt'].includes(command)) continue
      if (command === 'frac' || command === 'dfrac' || command === 'tfrac') {
        result += '(' + this.group(depth) + ')/(' + this.group(depth) + ')'; continue
      }
      if (command === 'sqrt') { result += '√(' + this.group(depth) + ')'; continue }
      result += symbols[command] ?? (command === 'left' || command === 'right' ? '' : command)
    }
    return result
  }
}
