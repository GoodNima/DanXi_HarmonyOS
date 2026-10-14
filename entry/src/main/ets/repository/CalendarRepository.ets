import { http } from '@kit.NetworkKit'
import { NetworkProxy } from '../common/NetworkProxy'
import { image } from '@kit.ImageKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { HttpUtil, HttpError } from '../util/HttpUtil'
import { FduRepository } from './FduRepository'
import { AcademicCalendar } from '../common/AcademicCalendar'
import { CalendarTerm, TeachingCalendar } from '../model/TeachingCalendar'
import { AppLanguage } from '../common/AppLanguage'
import { NativeCalendarRecognition } from '../util/NativeCalendarRecognition'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { CalendarEditions } from '../model/CalendarEditions'

/** The public calendar is also published by Fudan's information-disclosure site.
 * Scanned calendars are read on device, without uploading them to an OCR service.
 * Protected JWC pages share the same bounded CAS/browser verification as courses.
 */
export class CalendarRepository {
  // The /xl archive currently stops at 2023. Current university calendars are
  // published in the department's disclosure feed; try that live feed first.
  static readonly PUBLIC_LIST: string = 'https://xxgk.fudan.edu.cn/5229/list.htm'
  static readonly PUBLIC_ARCHIVE: string = 'https://xxgk.fudan.edu.cn/xl/list.htm'
  static readonly JWC_LIST: string = 'https://jwc.fudan.edu.cn/9385/list.htm'
  private static cacheDir: string = ''
  private static pending: Promise<CalendarTerm[]> | null = null
  private static retryAfter: number = 0

  static init(cacheDir: string): void { CalendarRepository.cacheDir = cacheDir }

  static async sync(force: boolean = false, allowAuthentication: boolean = false,
    canAuthenticate: () => boolean = (): boolean => true): Promise<CalendarTerm[]> {
    AcademicCalendar.publish()
    if (!force && AcademicCalendar.fresh()) return AcademicCalendar.cachedTerms()
    if (CalendarRepository.pending === null && !force && Date.now() < CalendarRepository.retryAfter) return AcademicCalendar.cachedTerms()
    // Public discovery is shared by all callers. Only an explicit, still-visible
    // request may escalate its own failed discovery to protected verification.
    if (CalendarRepository.pending === null) CalendarRepository.pending = CalendarRepository.loadPublic()
    const task: Promise<CalendarTerm[]> = CalendarRepository.pending
    const owner: string = AppStorage.get<string>('app_person') ?? ''
    try { const terms = await task; CalendarRepository.retryAfter = 0; return terms }
    catch (e) {
      CalendarRepository.retryAfter = Date.now() + 5 * 60 * 1000
      if (!allowAuthentication || !canAuthenticate() || owner !== (AppStorage.get<string>('app_person') ?? '')) throw e as Error
      const repository: FduRepository = FduRepository.getInstance()
      if (repository.needsVerification(CalendarRepository.JWC_LIST)) await repository.verifyService(CalendarRepository.JWC_LIST)
      if (!canAuthenticate() || owner !== (AppStorage.get<string>('app_person') ?? '')) throw e as Error
      const terms = await repository.withService(CalendarRepository.JWC_LIST,
        async (cookies: string): Promise<CalendarTerm[]> => CalendarRepository.readListing(CalendarRepository.JWC_LIST, cookies))
      if (!canAuthenticate() || owner !== (AppStorage.get<string>('app_person') ?? '')) throw e as Error
      await AcademicCalendar.store(terms)
      CalendarRepository.retryAfter = 0
      return terms
    }
    finally { if (CalendarRepository.pending === task) CalendarRepository.pending = null }
  }

  private static async loadPublic(): Promise<CalendarTerm[]> {
    let first: Error | undefined = undefined
    for (const listing of [CalendarRepository.PUBLIC_LIST, CalendarRepository.PUBLIC_ARCHIVE]) {
      try {
        const terms = await CalendarRepository.readListing(listing, '')
        await AcademicCalendar.store(terms)
        return terms
      } catch (e) { first = e as Error }
    }
    throw first ?? new Error(AppLanguage.text($r('app.string.calendar_sync_failed')))
  }

  static article(html: string, listing: string, now: Date = new Date()): string {
    const year = now.getMonth() < 7 ? now.getFullYear() - 1 : now.getFullYear()
    const anchors = html.match(/<a\b[^>]*>[\s\S]*?<\/a>/gi) ?? []
    for (const anchor of anchors) {
      if (!anchor.includes(String(year) + '-' + String(year + 1)) &&
        !anchor.includes(String(year) + '—' + String(year + 1))) continue
      if (!anchor.includes('校历')) continue
      const href = anchor.match(/href\s*=\s*["']([^"']+)["']/i)
      if (href) return CalendarRepository.officialUrl(href[1], listing)
    }
    return ''
  }

  static officialUrl(path: string, base: string): string {
    const origin = base.startsWith('https://jwc.fudan.edu.cn/') ? 'https://jwc.fudan.edu.cn' : 'https://xxgk.fudan.edu.cn'
    const url = path.startsWith('/') && !path.startsWith('//') ? origin + path : path
    return /^https:\/\/(?:jwc|xxgk)\.fudan\.edu\.cn\/[A-Za-z0-9_./%?=&-]+$/.test(url) ? url : ''
  }

  private static async readListing(url: string, cookies: string): Promise<CalendarTerm[]> {
    const params: Record<string, string> = {}
    params['calendar'] = String(new Date().getFullYear())
    const headers: Record<string, string> = {}
    if (cookies) headers['Cookie'] = cookies
    const response = await HttpUtil.getInstance().get(url, params, headers)
    const page = CalendarRepository.article(response.data, url)
    if (!page) throw new Error(AppLanguage.text($r('app.string.calendar_sync_failed')))
    return CalendarRepository.readArticle(page, cookies)
  }

  static async readArticle(page: string, cookies: string = ''): Promise<CalendarTerm[]> {
    const text = await CalendarRepository.readText(page, cookies)
    const terms = TeachingCalendar.parse(text, page)
    if (terms.length === 0) throw new Error(AppLanguage.text($r('app.string.calendar_unrecognized')))
    return terms
  }

  static async readText(page: string, cookies: string = ''): Promise<string> {
    const params: Record<string, string> = {}
    params['calendar'] = '1'
    const headers: Record<string, string> = {}
    if (cookies) headers['Cookie'] = cookies
    const response = await HttpUtil.getInstance().get(page, params, headers)
    const fromText = TeachingCalendar.parse(response.data.replace(/<[^>]+>/g, ''), page)
    if (fromText.length > 0) return response.data.replace(/<[^>]+>/g, '')
    const file = response.data.match(/(?:src|href|pdfsrc)\s*=\s*["']([^"']*\/_upload\/article\/[^"']+\.(?:pdf|png|jpe?g))["']/i)
    const url = file ? CalendarRepository.officialUrl(file[1], page) : ''
    if (!url) throw new Error(AppLanguage.text($r('app.string.calendar_sync_failed')))
    const bytes = await CalendarRepository.binary(url, cookies)
    const digest = cryptoFramework.createMd('SHA256')
    const blob: cryptoFramework.DataBlob = { data: new Uint8Array(bytes) }
    await digest.update(blob)
    const hash = (await digest.digest()).data
    let hex = ''
    for (const byte of hash) hex += byte.toString(16).padStart(2, '0')
    const verified = CalendarEditions.verifiedText(hex)
    if (verified) return verified
    try { return await (/\.pdf$/i.test(url) ? CalendarRepository.pdfText(bytes) : CalendarRepository.imageText(bytes)) }
    catch (e) { throw new Error(AppLanguage.text($r('app.string.calendar_unrecognized'))) }
  }

  private static async binary(url: string, cookies: string): Promise<ArrayBuffer> {
    const request = http.createHttp()
    const hops: Record<string, string>[] = []
    request.on('headersReceive', (headers: Object) => { hops.push(headers as Record<string, string>) })
    try {
      const headers: Record<string, string> = {}
      if (cookies) headers['Cookie'] = cookies
      const response = await request.request(url, NetworkProxy.apply({ method: http.RequestMethod.GET,
        header: headers, expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: true, connectTimeout: 10000, readTimeout: 15000 }))
      if (HttpUtil.requiresCampusLogin(url, hops)) throw new HttpError(-2, 0, AppLanguage.text($r('app.string.calendar_login_required')), '')
      if (response.responseCode !== 200) throw new HttpError(response.responseCode, 0, 'HTTP ' + response.responseCode, '')
      const bytes = response.result as ArrayBuffer
      if (bytes.byteLength === 0 || bytes.byteLength > 12 * 1024 * 1024) throw new Error(AppLanguage.text($r('app.string.calendar_unrecognized')))
      return bytes
    } catch (e) {
      if (e instanceof Error) throw e
      throw new HttpError(-1, (e as BusinessError).code, AppLanguage.text($r('app.string.calendar_sync_failed')), '')
    } finally { request.destroy() }
  }

  private static async recognize(map: image.PixelMap): Promise<string> {
    return NativeCalendarRecognition.recognize(map)
  }

  private static async imageText(bytes: ArrayBuffer): Promise<string> {
    const source = image.createImageSource(bytes)
    try {
      const map = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 })
      return await CalendarRepository.recognize(map)
    } finally { await source.release() }
  }

  private static async pdfText(bytes: ArrayBuffer): Promise<string> {
    if (!CalendarRepository.cacheDir) throw new Error(AppLanguage.text($r('app.string.calendar_sync_failed')))
    const path = CalendarRepository.cacheDir + '/official-calendar-' + String(Date.now()) + '.pdf'
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC)
    try { fs.writeSync(file.fd, bytes) } finally { fs.closeSync(file) }
    try { return await NativeCalendarRecognition.pdfText(path) }
    finally { fs.unlinkSync(path) }
  }
}
