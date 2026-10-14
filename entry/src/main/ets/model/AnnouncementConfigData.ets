/** Public upstream announcement fields used by AutoBanner and the campus greeting. */
export class AnnouncementBanner {
  title: string = ''
  button: string = ''
  action: string = ''
}
export class AnnouncementCelebration {
  date: string = ''
  words: string[] = []
}
export class DeveloperNotice {
  content: string = ''
  updatedAt: string = ''
  maxBuild: number = 0
}
export class AnnouncementSnapshot {
  banners: AnnouncementBanner[] = []
  celebrations: AnnouncementCelebration[] = []
  notices: DeveloperNotice[] = []
  cachedAt: number = 0
  checkedAt: number = 0
  loading: boolean = false
  error: string = ''
}

/** A bounded parser for the upstream public [[banners]] / [[celebrations]] schema.
 * It does not execute TOML values or treat error HTML as an empty valid config. */
export class AnnouncementConfigParser {
  static parse(text: string): AnnouncementSnapshot {
    if (!text.trim() || text.length > 512 * 1024 || /^\s*</.test(text)) throw new Error('活动配置格式无效')
    const out = new AnnouncementSnapshot()
    let banner: AnnouncementBanner | null = null
    let celebration: AnnouncementCelebration | null = null
    let notice: DeveloperNotice | null = null
    let syntax: boolean = false
    for (const statement of AnnouncementConfigParser.statements(text)) {
      if (statement.startsWith('[')) {
        syntax = true
        banner = null
        celebration = null
        notice = null
        if (statement === '[[banners]]' && out.banners.length < 64) {
          banner = new AnnouncementBanner(); out.banners.push(banner)
        } else if (statement === '[[celebrations]]' && out.celebrations.length < 128) {
          celebration = new AnnouncementCelebration(); out.celebrations.push(celebration)
        } else if (statement === '[[dev_notice]]' && out.notices.length < 128) {
          notice = new DeveloperNotice(); out.notices.push(notice)
        }
        continue
      }
      // TOML bare keys may start with a digit. The real shared configuration
      // includes semester_start_date.527, unrelated to banners but still valid.
      const match = /^([A-Za-z0-9_-]+)\s*=\s*([\s\S]+)$/.exec(statement)
      if (match === null) throw new Error('活动配置格式无效')
      syntax = true
      const name: string = match[1]
      const value: string = match[2].trim()
      if (banner !== null && ['title', 'button', 'action'].includes(name)) {
        const decoded = AnnouncementConfigParser.string(value)
        if (name === 'title') banner.title = decoded.slice(0, 1024)
        if (name === 'button') banner.button = decoded.slice(0, 128)
        if (name === 'action') banner.action = decoded.slice(0, 8192)
      }
      if (celebration !== null) {
        if (name === 'date') celebration.date = AnnouncementConfigParser.string(value).slice(0, 32)
        if (name === 'words') celebration.words = AnnouncementConfigParser.strings(value).slice(0, 32)
      }
      if (notice !== null) {
        if (name === 'content') notice.content = AnnouncementConfigParser.string(value).slice(0, 65536)
        if (name === 'updated_at') notice.updatedAt = AnnouncementConfigParser.string(value).slice(0, 64)
        if (name === 'build') {
          if (!/^\d+$/.test(value) || !Number.isSafeInteger(Number(value))) throw new Error('公告版本格式无效')
          notice.maxBuild = Number(value)
        }
      }
    }
    if (!syntax) throw new Error('活动配置格式无效')
    out.banners = out.banners.filter((row: AnnouncementBanner) => row.title.trim().length > 0 &&
      (row.action.length === 0 || AnnouncementConfigParser.validAction(row.action)))
    out.celebrations = out.celebrations.filter((row: AnnouncementCelebration) =>
      row.date.length > 0 && row.words.length > 0)
    out.notices = out.notices.filter((row: DeveloperNotice) => row.content.trim().length > 0 &&
      Number.isFinite(AnnouncementConfigParser.noticeDate(row.updatedAt)))
      .sort((a: DeveloperNotice, b: DeveloperNotice) => AnnouncementConfigParser.noticeDate(b.updatedAt) - AnnouncementConfigParser.noticeDate(a.updatedAt))
    return out
  }

  static noticeDate(value: string): number { return Date.parse(value.replace(/([+-]\d{2})(\d{2})$/, '$1:$2')) }

  static validAction(action: string): boolean {
    return /^##?[1-9]\d*$/.test(action) || /^https?:\/\/[^\s<>]+$/i.test(action)
  }

  private static statements(text: string): string[] {
    const out: string[] = []
    let line: string = ''
    let quote: string = ''
    let depth: number = 0
    let escape: boolean = false
    let comment: boolean = false
    let triple: boolean = false
    for (let i: number = 0; i < text.length; i++) {
      const c = text.charAt(i)
      if (comment) { if (c !== '\n') continue; comment = false }
      if (quote) {
        line += c
        if (escape) { escape = false; continue }
        if (quote === '"' && c === '\\') { escape = true; continue }
        if (c === quote && (!triple || text.substring(i, i + 3) === quote.repeat(3))) {
          if (triple) { line += quote.repeat(2); i += 2 }
          quote = ''; triple = false
        }
        continue
      }
      if (c === '#') { comment = true; continue }
      if (c === '"' || c === "'") {
        quote = c
        triple = text.substring(i, i + 3) === c.repeat(3)
        line += triple ? c.repeat(3) : c
        if (triple) i += 2
      } else if (c === '[' || c === '{') { depth++; line += c }
      else if (c === ']' || c === '}') { depth--; line += c; if (depth < 0) throw new Error('活动配置括号无效') }
      else if (c === '\n' && depth === 0) { if (line.trim()) out.push(line.trim()); line = '' }
      else line += c
    }
    if (quote || depth !== 0) throw new Error('活动配置不完整')
    if (line.trim()) out.push(line.trim())
    return out
  }

  private static string(value: string): string {
    const q = value.charAt(0)
    if ((q !== '"' && q !== "'") || !value.endsWith(q)) throw new Error('活动配置文字无效')
    const triple = value.startsWith(q.repeat(3)) && value.endsWith(q.repeat(3))
    let body = value.substring(triple ? 3 : 1, value.length - (triple ? 3 : 1))
    if (triple && body.startsWith('\n')) body = body.substring(1)
    if (q === "'") return body
    if (triple) body = body.replace(/\r?\n/g, '\\n').replace(/\t/g, '\\t').replace(/(?<!\\)"/g, '\\"')
    try { return JSON.parse('"' + body + '"') as string } catch (e) { throw new Error('活动配置转义无效') }
  }

  private static strings(value: string): string[] {
    if (!value.startsWith('[') || !value.endsWith(']')) throw new Error('活动祝福格式无效')
    const source = value.substring(1, value.length - 1)
    const out: string[] = []
    let quote: string = ''
    let escaped: boolean = false
    let token: string = ''
    for (let i: number = 0; i < source.length; i++) {
      const c = source.charAt(i)
      if (quote) {
        token += c
        if (escaped) escaped = false
        else if (quote === '"' && c === '\\') escaped = true
        else if (c === quote) quote = ''
      } else if (c === '"' || c === "'") { quote = c; token += c }
      else if (c === ',') { if (token.trim()) out.push(AnnouncementConfigParser.string(token.trim())); token = '' }
      else token += c
    }
    if (quote) throw new Error('活动祝福不完整')
    if (token.trim()) out.push(AnnouncementConfigParser.string(token.trim()))
    return out.filter((word: string) => word.trim().length > 0).map((word: string) => word.slice(0, 1024))
  }
}
