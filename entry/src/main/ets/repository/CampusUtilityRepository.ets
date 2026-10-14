import { HttpUtil, HttpError } from '../util/HttpUtil'
import { AppLanguage } from '../common/AppLanguage'
import { CampusHtml } from '../model/CampusHtml'
import { CampusAccessCard, ExerciseItem, ExerciseRecord, SportsSnapshot, LifeCode, LifeCodeTermsError } from '../model/CampusUtility'

interface AccessEnvelope { data?: Object[][] }

/** Exact upstream read-only contracts. Session acquisition belongs to the
 * shared FduRepository; this repository never submits consent or applications. */
export class CampusUtilityRepository {
  static readonly SPORTS_URL: string = 'https://fdtyjw.fudan.edu.cn/sportScore/stScore.aspx'
  static readonly SPORTS_GUIDE_URL: string = 'https://fdty.fudan.edu.cn/_upload/article/files/a5/20/7678c8f5411d9407085d9d22e248/fd4a3077-f435-43f3-ba72-d2167a398de6.pdf'
  static readonly SPORTS_RULES_URL: string = 'https://fdty.fudan.edu.cn/5b/c8/c29222a482248/page.htm'
  static readonly ACCESS_URL: string = 'https://my.fudan.edu.cn/data_tables/ykt_xx.json'
  static readonly LIFE_CODE_URL: string = 'https://ecard.fudan.edu.cn/epay/wxpage/fudan/zfm/qrcode'

  static async sports(cookies: string): Promise<SportsSnapshot> {
    const response = await HttpUtil.getInstance().get(CampusUtilityRepository.SPORTS_URL, undefined,
      { 'Cookie': cookies, 'Accept': 'text/html', 'User-Agent': HttpUtil.BROWSER_UA })
    return CampusUtilityRepository.parseSports(response.data)
  }
  static async access(cookies: string): Promise<CampusAccessCard[]> {
    // Upstream uses POST with no body to this DataTables read endpoint.
    const response = await HttpUtil.getInstance().post(CampusUtilityRepository.ACCESS_URL, undefined,
      { 'Cookie': cookies, 'Referer': 'https://my.fudan.edu.cn/', 'User-Agent': HttpUtil.BROWSER_UA })
    return CampusUtilityRepository.parseAccess(response.data)
  }
  static async lifeCode(cookies: string): Promise<LifeCode> {
    const response = await HttpUtil.getInstance().get(CampusUtilityRepository.LIFE_CODE_URL, undefined,
      { 'Cookie': cookies, 'Accept': 'text/html', 'User-Agent': HttpUtil.BROWSER_UA })
    return CampusUtilityRepository.parseLifeCode(response.data)
  }
  static parseSports(html: string): SportsSnapshot {
    const root = CampusHtml.parse(html)
    const table = root.findId('pAll')?.direct('table')[0]
    const rows = table?.rows() ?? []
    const countTable = rows[5]?.direct('td')[0]?.direct('table')[0]
    if (countTable === undefined || countTable.rows().length === 0) throw new HttpError(200, 0, AppLanguage.text($r('app.string.utility_invalid_response')), '')
    const result = new SportsSnapshot()
    for (const row of countTable.rows()) {
      const cells = row.direct('td')
      for (let i: number = 0; i + 1 < cells.length; i += 2) {
        const title = cells[i].text().replace('：', '').trim()
        if (!title) continue
        const item = new ExerciseItem(); item.title = title
        const text = cells[i + 1].text()
        if (/^\d+$/.test(text)) item.times = Number(text)
        result.items.push(item)
      }
    }
    const scoreTable = rows[25]?.direct('td')[0]?.direct('table')[0]
    const scoreCells = scoreTable?.rows().flatMap(row => row.direct('td')) ?? []
    for (let i: number = 0; i + 5 < scoreCells.length; i += 6) {
      const record = new ExerciseRecord()
      record.title = scoreCells[i + 1].text(); record.result = scoreCells[i + 2].text()
      record.score = scoreCells[i + 3].text(); record.comment = scoreCells[i + 4].text()
      if (record.title) result.records.push(record)
    }
    result.updatedAt = Date.now()
    return result
  }
  static parseAccess(body: string): CampusAccessCard[] {
    let envelope: AccessEnvelope
    try { envelope = JSON.parse(body) as AccessEnvelope } catch (e) { throw new HttpError(200, 0, AppLanguage.text($r('app.string.utility_invalid_response')), '') }
    if (envelope === null || !Array.isArray(envelope.data)) throw new HttpError(200, 0, AppLanguage.text($r('app.string.utility_invalid_response')), '')
    const result: CampusAccessCard[] = []
    for (const row of envelope.data) {
      if (!Array.isArray(row) || row.length < 6) throw new HttpError(200, 0, AppLanguage.text($r('app.string.utility_invalid_response')), '')
      const item = new CampusAccessCard()
      item.id = CampusUtilityRepository.cell(row[0]); item.name = CampusUtilityRepository.cell(row[1])
      item.status = CampusUtilityRepository.cell(row[2]); item.permission = CampusUtilityRepository.cell(row[3])
      item.expireDate = CampusUtilityRepository.cell(row[4]); item.balance = CampusUtilityRepository.cell(row[5])
      if (!item.id) throw new HttpError(200, 0, AppLanguage.text($r('app.string.utility_invalid_response')), '')
      result.push(item)
    }
    return result
  }
  static parseLifeCode(html: string): LifeCode {
    const root = CampusHtml.parse(html)
    const value = root.findId('myText')?.attributes['value'] ?? ''
    if (!value) {
      if (root.findId('btn-agree-ok') !== undefined) throw new LifeCodeTermsError()
      throw new HttpError(200, 0, AppLanguage.text($r('app.string.utility_invalid_response')), '')
    }
    // ArkUI QRCode truncates >512 characters: reject rather than display an invalid credential.
    if (value.length > 512) throw new HttpError(200, 0, AppLanguage.text($r('app.string.utility_code_too_long')), '')
    const result = new LifeCode(); result.value = value; result.updatedAt = Date.now(); return result
  }
  private static cell(value: Object | null | undefined): string {
    if (typeof value !== 'string' && typeof value !== 'number') return ''
    return String(value).trim()
  }
}
