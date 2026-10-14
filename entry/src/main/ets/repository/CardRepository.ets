/**
 * Campus card (一卡通) access — ported from
 * lib/repository/fdu/ecard_repository.dart (`CardRepository`).
 *
 * WHAT THIS TALKS TO
 * ------------------
 * Four URLs on ecard.fudan.edu.cn, all behind the Fudan ID login:
 *
 *   GET  /epay                       entry point (starts the CAS dance)
 *   GET  /epay/myepay/index          name + balance
 *   GET  /epay/consume/index         HTML carrying the `_csrf` token
 *   POST /epay/consume/query         transaction rows, XML in a CDATA wrapper
 *
 * THE SERVICE STRING (discovered, not guessed)
 * --------------------------------------------
 * A CAS ticket is bound to exactly one service, so the login has to be run
 * against the right one. Requesting any of these pages anonymously answers:
 *
 *   302 -> https://id.fudan.edu.cn/idp/authCenter/authenticate
 *          ?service=https%3A%2F%2Fecard.fudan.edu.cn%2Fepay%2Fj_spring_cas_security_check
 *
 * so the service is `https://ecard.fudan.edu.cn/epay/j_spring_cas_security_check`
 * — NOT the `/epay` entry point, which merely redirects into it. Measured on
 * 2026-09-29 by following the chain hop by hop.
 *
 * WHAT IS AND IS NOT VERIFIED
 * ---------------------------
 * The request construction and the parsers below are faithful to the upstream
 * Dart, and the parsers are unit-tested. The LIVE response format has not been
 * observed, because that needs a real Fudan ID session. So: this code fails
 * loudly at login rather than returning anything invented, and nothing here
 * should be described as "verified against the live service" until someone runs
 * it with an account.
 */

import { BaseRepository } from './BaseRepository'
import { HttpError, HttpUtil, HttpResponse } from '../util/HttpUtil'
import { CardInfo, CardRecord } from '../model/Card'

interface RecordCacheEntry { days: number; date: string; saved: number; rows: CardRecord[] }

export class CardRepository extends BaseRepository {
  private static instance: CardRepository | null = null

  /**
   * The CAS service this repository needs a ticket for.
   *
   * Taken from the `service` parameter the server itself puts in its redirect
   * (see the header comment). Using `/epay` instead would issue a ticket for a
   * URL that immediately redirects again, which CAS rejects.
   */
  static readonly SERVICE: string =
    'https://ecard.fudan.edu.cn/epay/j_spring_cas_security_check'

  private static readonly HOST: string = 'https://ecard.fudan.edu.cn'
  private static readonly USER_DETAIL_URL: string = CardRepository.HOST + '/epay/myepay/index'
  private static readonly CONSUME_DETAIL_URL: string = CardRepository.HOST + '/epay/consume/query'
  private static readonly CONSUME_CSRF_URL: string = CardRepository.HOST + '/epay/consume/index'

  /**
   * The consume endpoint is picky about the request looking like the page that
   * calls it, so the upstream sends a full browser header set including Origin
   * and Referer. Kept verbatim (Firefox 84 string included) because a mismatch
   * here shows up as a generic 403 rather than a useful error.
   */
  private static readonly CONSUME_UA: string =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:84.0) Gecko/20100101 Firefox/84.0'

  /** Session cookies for ecard.fudan.edu.cn, or '' while logged out. */
  private campusCookies: string = ''
  private activeQueries: number = 0
  private queryWaiters: Array<() => void> = []
  private generation: number = 0
  private recordCache: RecordCacheEntry[] = []
  private csrf: string = ''
  private csrfAt: number = 0
  private balance: CardInfo | null = null
  private balanceAt: number = 0
  private balancePending: Promise<CardInfo> | null = null
  private csrfPending: Promise<string> | null = null
  private pending: Map<number, Promise<CardRecord[]>> = new Map<number, Promise<CardRecord[]>>()

  invalidate(): void {
    this.generation++
    this.recordCache = []
    this.csrf = ''
    this.balance = null
    this.balancePending = null
    this.csrfPending = null
    this.pending.clear()
  }

  private assertCurrent(generation: number): void {
    if (generation !== this.generation) throw new Error('一卡通会话已更新，请重试')
  }

  private constructor() {
    super()
  }

  static getInstance(): CardRepository {
    if (!CardRepository.instance) {
      CardRepository.instance = new CardRepository()
    }
    return CardRepository.instance
  }

  /**
   * Hand this repository the cookie string produced by a login against
   * `CardRepository.SERVICE`. Without it every call below fails.
   */
  setSession(cookies: string): void {
    if (this.campusCookies !== cookies) this.invalidate()
    this.campusCookies = cookies
  }

  hasSession(): boolean {
    return this.campusCookies.length > 0
  }

  private sessionError(): HttpError {
    return new HttpError(
      0,
      0,
      '一卡通需要先用复旦 ID 登录（服务 ' + CardRepository.SERVICE + '）。',
      ''
    )
  }

  private sessionHeaders(referer?: string): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': CardRepository.CONSUME_UA,
      'Accept-Language': 'zh-CN,en-US;q=0.7,en;q=0.3',
      'Cookie': this.campusCookies,
    }
    if (referer !== undefined) {
      headers['Referer'] = referer
    }
    return headers
  }

  // ─────────────────────────────── parsing ───────────────────────────────

  /**
   * Pull the CSRF token out of `<meta name="_csrf" content="...">`.
   *
   * The attribute order is not guaranteed, so both orders are tried. Returns ''
   * when absent; the caller decides whether that is fatal (it is: a consume
   * query without `_csrf` is rejected, and silently sending an empty token would
   * look like an expired session).
   */
  static parseCsrf(html: string): string {
    const nameFirst = /<meta[^>]*name=["']?_csrf["']?[^>]*content=["']([^"']+)["']/i.exec(html)
    if (nameFirst !== null) {
      return nameFirst[1]
    }
    const contentFirst = /<meta[^>]*content=["']([^"']+)["'][^>]*name=["']?_csrf["']?/i.exec(html)
    if (contentFirst !== null) {
      return contentFirst[1]
    }
    return ''
  }

  /**
   * The consume response is an XML document wrapped in `<![CDATA[ ... ]]>`
   * (upstream: `data!.between("<![CDATA[", "]]>")`). Returns the inner HTML, or
   * the input unchanged when there is no wrapper, so a server that stops using
   * CDATA still parses.
   */
  static extractCdata(body: string): string {
    const start: number = body.indexOf('<![CDATA[')
    if (start < 0) {
      return body
    }
    const end: number = body.indexOf(']]>', start)
    if (end < 0) {
      return body.substring(start + 9)
    }
    return body.substring(start + 9, end)
  }

  /** Strip tags and unescape the entities these tables actually contain. */
  private static cellText(cell: string): string {
    return cell
      .replace(/<[^>]*>/g, ' ')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, '\'')
      .replace(/\s+/g, ' ')
      .trim()
  }

  /**
   * Parse the transaction rows.
   *
   * The upstream walks `tbody > tr > td` with BeautifulSoup and reads the cells
   * positionally. There is no HTML parser dependency in this project, so the
   * same structure is recovered with two regex passes.
   *
   * The first cell is special: upstream reads its first two CHILD ELEMENTS as
   * the date and the time. Rather than assume a tag layout (which was never
   * observed), both are pulled out by shape — a `yyyy.MM.dd` token and an
   * `HH:mm` token. The site writes dates with dots, which the upstream converts
   * to dashes before building the timestamp.
   *
   * A row that yields neither is SKIPPED rather than emitted half-empty: a
   * missing timestamp cannot be honestly represented.
   */
  static parseRecords(cdataHtml: string): CardRecord[] {
    const records: CardRecord[] = []
    const rowPattern = /<tr[^>]*>([\s\S]*?)<\/tr>/gi
    let row: RegExpExecArray | null = rowPattern.exec(cdataHtml)
    while (row !== null) {
      const cells: string[] = []
      const cellPattern = /<td[^>]*>([\s\S]*?)<\/td>/gi
      let cell: RegExpExecArray | null = cellPattern.exec(row[1])
      while (cell !== null) {
        cells.push(cell[1])
        cell = cellPattern.exec(row[1])
      }

      if (cells.length >= 4) {
        const dateMatch = /([0-9]{4})[.\-/]([0-9]{1,2})[.\-/]([0-9]{1,2})/.exec(cells[0])
        const timeMatch = /([0-9]{1,2}:[0-9]{2})/.exec(cells[0])
        if (dateMatch !== null && timeMatch !== null) {
          const month: string = dateMatch[2].length === 1 ? '0' + dateMatch[2] : dateMatch[2]
          const day: string = dateMatch[3].length === 1 ? '0' + dateMatch[3] : dateMatch[3]
          const item: CardRecord = {
            time: dateMatch[1] + '-' + month + '-' + day + 'T' + timeMatch[1],
            type: CardRepository.cellText(cells[1]),
            location: CardRepository.cellText(cells[2]),
            payment: CardRepository.cellText(cells[3]),
          }
          records.push(item)
        }
      }
      row = rowPattern.exec(cdataHtml)
    }
    return records
  }

  /**
   * Total page count, from the `</b>/N页` marker the pagination widget emits
   * (upstream: `data.between('</b>/', '页')`). Returns 1 when absent, matching
   * the upstream default of a single page.
   */
  static parseTotalPages(body: string): number {
    const match = /<\/b>\s*\/\s*([0-9]+)\s*页/.exec(body)
    if (match === null) {
      return 1
    }
    const pages: number = parseInt(match[1], 10)
    return pages > 0 ? pages : 1
  }

  /**
   * Name and balance from the `myepay` page.
   *
   * Upstream selectors: `.custname` for the name (text between 您好， and ！)
   * and `.payway-box-bottom-item>p` for the balance. Both are matched by class
   * attribute, which survives the surrounding markup changing.
   */
  static parseCardInfo(html: string): CardInfo {
    let name: string = ''
    const nameElement = /class=["'][^"']*custname[^"']*["'][^>]*>([\s\S]*?)<\//i.exec(html)
    if (nameElement !== null) {
      const raw: string = CardRepository.cellText(nameElement[1])
      const greets: number = raw.indexOf('您好，')
      const bang: number = raw.lastIndexOf('！')
      if (greets >= 0 && bang > greets) {
        name = raw.substring(greets + 3, bang).trim()
      } else if (raw.length > 0) {
        name = raw
      }
    }

    let cash: string = ''
    const cashElement =
      /class=["'][^"']*payway-box-bottom-item[^"']*["'][^>]*>[\s\S]*?<p[^>]*>([\s\S]*?)<\/p>/i.exec(html)
    if (cashElement !== null) {
      cash = CardRepository.cellText(cashElement[1])
    }

    const info: CardInfo = { name: name, cash: cash, records: [] }
    return info
  }

  // ─────────────────────────────── requests ───────────────────────────────

  /**
   * Balance and holder name.
   *
   * `logDays` follows the upstream contract exactly:
   *   > 0  records of the last N days
   *   = 0  the latest records (upstream fetches 30 days, one page)
   *   < 0  no records at all, identity only
   *
   * An empty name is treated as a failed session, matching upstream's
   * `throw Exception("Unable to get user name")`. That page is only served to a
   * live session, so an empty name means we were handed the login shell — which
   * must not be rendered as an account with no name and no balance.
   */
  async getCardInfo(logDays: number = 0): Promise<CardInfo> {
    if (!this.hasSession()) throw this.sessionError()
    let info = this.balance
    if (info === null || Date.now() - this.balanceAt > 60000) {
      if (this.balancePending === null) {
        const generation = this.generation
        const request = this.loadBalance(generation)
        this.balancePending = request
        request.finally(() => { if (this.balancePending === request) this.balancePending = null }).catch(() => {})
      }
      info = await this.balancePending
    }
    return { name: info.name, cash: info.cash, records: await this.getCardRecords(logDays) }
  }

  private async loadBalance(generation: number): Promise<CardInfo> {
    const response = await this.httpUtil.get(CardRepository.USER_DETAIL_URL, undefined, this.sessionHeaders())
    this.assertCurrent(generation)
    const info = CardRepository.parseCardInfo(response.data)
    if (!info.name) throw new HttpError(-2, 0, '一卡通会话已失效，请重新登录。', '')
    this.balance = info
    this.balanceAt = Date.now()
    return info
  }

  /** CSRF token required by the consume endpoint. */
  private async fetchCsrf(): Promise<string> {
    if (this.csrf && Date.now() - this.csrfAt < 300000) return this.csrf
    if (this.csrfPending !== null) return this.csrfPending
    const generation = this.generation
    const request = this.loadCsrf(generation)
    this.csrfPending = request
    try { return await request }
    finally { if (this.csrfPending === request) this.csrfPending = null }
  }

  private async loadCsrf(generation: number): Promise<string> {
    const response: HttpResponse = await this.httpUtil.get(
      CardRepository.CONSUME_CSRF_URL,
      undefined,
      this.sessionHeaders()
    )
    const token: string = CardRepository.parseCsrf(response.data)
    if (token.length === 0) {
      throw new HttpError(
        response.code,
        0,
        '一卡通 CSRF 令牌缺失，会话可能已失效。',
        response.data
      )
    }
    this.assertCurrent(generation)
    this.csrf = token
    this.csrfAt = Date.now()
    return token
  }

  /**
   * Transaction rows.
   *
   * Date ranges read all pages; latest records read one page. The first page
   * provides both its rows and the page count, without a duplicate request.
   */
  async getCardRecords(logDays: number = 0, onProgress?: (page: number, total: number) => void,
    onRows?: (rows: CardRecord[]) => void): Promise<CardRecord[]> {
    if (logDays < 0) return []
    if (!this.hasSession()) throw this.sessionError()
    const today = CardRepository.formatDate(new Date())
    const cutoff = CardRepository.formatDate(new Date(Date.now() - (logDays || 30) * 86400000))
    const cached = this.recordCache.find((item: RecordCacheEntry) => item.date === today &&
      Date.now() - item.saved < 300000 && (item.days === logDays || (item.days > 0 && item.days >= (logDays || 30))))
    if (cached !== undefined) {
      let rows = cached.rows.filter((row: CardRecord) => row.time.substring(0, 10) >= cutoff)
      if (logDays === 0) rows = rows.slice(0, 10)
      if (onRows !== undefined) onRows(rows.slice())
      return rows.slice()
    }
    const existing = this.pending.get(logDays)
    if (existing !== undefined) return existing
    const generation = this.generation
    const request = this.loadRecords(logDays, generation, onProgress, onRows)
    this.pending.set(logDays, request)
    try { return await request }
    finally { if (this.pending.get(logDays) === request) this.pending.delete(logDays) }
  }

  private async loadRecords(logDays: number, generation: number,
    onProgress?: (page: number, total: number) => void, onRows?: (rows: CardRecord[]) => void): Promise<CardRecord[]> {
    const csrf: string = await this.fetchCsrf()
    const backDays: number = logDays === 0 ? 30 : logDays
    const end: Date = new Date()
    const start: Date = new Date(end.getTime() - backDays * 24 * 60 * 60 * 1000)

    const fields: Record<string, string> = {
      'aaxmlrequest': 'true',
      'pageNo': '1',
      'tabNo': '1',
      'pager.offset': '10',
      'tradename': '',
      'starttime': CardRepository.formatDate(start),
      'endtime': CardRepository.formatDate(end),
      'timetype': '1',
      '_tradedirect': 'on',
      '_csrf': csrf,
    }

    this.assertCurrent(generation)
    const first: HttpResponse = await this.postConsumePage(fields)
    const totalPages = logDays > 0 ? CardRepository.parseTotalPages(first.data) : 1
    const all: CardRecord[] = CardRepository.readRecordPage(first.data)
    if (logDays > 0 && all.length >= 10 && !/<\/b>\s*\/\s*[0-9]+\s*页/.test(first.data)) {
      throw new HttpError(200, 0, '无法读取交易总页数，请重试。', '')
    }
    this.assertCurrent(generation)
    if (onProgress !== undefined) onProgress(1, totalPages)
    if (onRows !== undefined) onRows(all.slice())
    // Three requests per batch: preserve server order and avoid flooding the campus service.
    for (let page = 2; page <= totalPages; page += 3) {
      this.assertCurrent(generation)
      const batch: Promise<CardRecord[]>[] = []
      for (let offset = 0; offset < 3 && page + offset <= totalPages; offset++) {
        const pageFields: Record<string, string> = {}
        for (const key of Object.keys(fields)) pageFields[key] = fields[key]
        pageFields['pageNo'] = String(page + offset)
        batch.push(this.postConsumePage(pageFields).then((response: HttpResponse) => CardRepository.readRecordPage(response.data)))
      }
      const results = await Promise.all(batch)
      this.assertCurrent(generation)
      for (const rows of results) all.push(...rows)
      if (onProgress !== undefined) onProgress(Math.min(page + 2, totalPages), totalPages)
      if (onRows !== undefined) onRows(all.slice())
    }
    this.recordCache = this.recordCache.filter((item: RecordCacheEntry) => item.days !== logDays)
    this.recordCache.push({ days: logDays, date: CardRepository.formatDate(end), saved: Date.now(), rows: all.slice() })
    return all
  }

  private static readRecordPage(body: string): CardRecord[] {
    const html = CardRepository.extractCdata(body)
    if (!/<tbody\b/i.test(html) && !/暂无|没有.*记录|无交易记录|查询结果为空/.test(html)) {
      throw new HttpError(200, 0, '无法解析一卡通交易记录，请重试。', '')
    }
    return CardRepository.parseRecords(html)
  }

  private async postConsumePage(fields: Record<string, string>): Promise<HttpResponse> {
    const headers: Record<string, string> = this.sessionHeaders(
      CardRepository.CONSUME_CSRF_URL
    )
    headers['Accept'] = 'text/xml'
    headers['Origin'] = CardRepository.HOST
    headers['DNT'] = '1'
    headers['Connection'] = 'keep-alive'
    headers['Sec-GPC'] = '1'
    const generation = this.generation
    if (this.activeQueries >= 3) await new Promise<void>((resolve) => { this.queryWaiters.push(resolve) })
    else this.activeQueries++
    try {
      this.assertCurrent(generation)
      return await this.httpUtil.postForm(CardRepository.CONSUME_DETAIL_URL, fields, headers)
    } finally {
      const next = this.queryWaiters.shift()
      if (next !== undefined) next()
      else this.activeQueries--
    }
  }

  /** `yyyy-MM-dd`, the format the consume query expects. */
  private static formatDate(date: Date): string {
    const month: string = date.getMonth() + 1 < 10
      ? '0' + String(date.getMonth() + 1)
      : String(date.getMonth() + 1)
    const day: string = date.getDate() < 10
      ? '0' + String(date.getDate())
      : String(date.getDate())
    return String(date.getFullYear()) + '-' + month + '-' + day
  }
}
