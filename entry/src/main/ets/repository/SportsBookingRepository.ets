import { SportsBooking, BookingVenue, BookingDetail, BookingCalendar, BookingAppointments, BookingOccupants, BookingPeriod, BookingContact, BookingLaunch, BookingLaunchResult } from '../model/SportsBooking'
import { HttpUtil } from '../util/HttpUtil'
import { FduRepository } from './FduRepository'
import { AppState } from '../common/AppState'
import { CampusCookies } from '../common/CampusCookies'
import { BookingBrowserTransport } from '../common/BookingBrowserTransport'
import { HttpError } from '../util/HttpUtil'

interface BookingCache { body: string; at: number }
interface BookingDateRange { start_date: string; end_date: string }
export interface SportsBookingSource {
  owner(): string
  venues(force: boolean): Promise<BookingVenue[]>
  detail(id: number, force: boolean): Promise<BookingDetail>
  calendar(id: number, day: string, force: boolean): Promise<BookingCalendar>
  appointments(page: number, force: boolean): Promise<BookingAppointments>
  occupants(id: number, resources: number[], day: string, period: BookingPeriod, page: number): Promise<BookingOccupants>
  contact(): Promise<BookingContact>
  launch(value: BookingLaunch): Promise<BookingLaunchResult>
  cancel(value: number, details: number[]): Promise<void>
  verify(): Promise<void>
}
/** Latest iOS JSON protocol: one paginated topic catalogue, bounded per-account
 * caches and joined reads. Filters/search never repeat a network request. */
export class SportsBookingRepository implements SportsBookingSource {
  private static cache: Map<string, BookingCache> = new Map()
  private static flights: Map<string, Promise<string>> = new Map()
  private static mutations: Map<string, Promise<string>> = new Map()
  owner(): string { return AppState.getPerson().getStudentId() + '/' + CampusCookies.generation() + '/' + AppState.isLoggedIn() }
  private headers(path: string, method: string, referer: string, signed: boolean, cookies: string): Record<string, string> {
    const headers: Record<string, string> = {}
    headers['User-Agent'] = HttpUtil.BROWSER_UA; headers['Accept'] = 'application/json, text/plain, */*'
    headers['Referer'] = referer; headers['Cookie'] = cookies; headers['Authorization'] = ''
    if (signed) headers['sign-key'] = path + method.toLowerCase()
    return headers
  }
  private read(path: string, query: string, referer: string, force: boolean = false, ttl: number = 60000, signed: boolean = true): Promise<string> {
    const owner: string = this.owner(), key: string = owner + '/' + path + query
    const cached = SportsBookingRepository.cache.get(key)
    if (!force && cached !== undefined && Date.now() - cached.at < ttl) return Promise.resolve(cached.body)
    const joined = SportsBookingRepository.flights.get(key); if (joined !== undefined) return joined
    const task = FduRepository.getInstance().withService(SportsBooking.LOGIN, async (cookies: string): Promise<string> => {
      const url: string = SportsBooking.ORIGIN + path + query, headers = this.headers(path, 'GET', referer, signed, cookies)
      let body: string
      try { body = (await HttpUtil.getInstance().get(url, undefined, headers)).data }
      catch (e) {
        if (!(e instanceof HttpError) || e.statusCode !== 412) throw e as Error
        body = await BookingBrowserTransport.read(url, headers)
      }
      SportsBooking.data<Object>(body); return body
    }).then((body: string): string => {
      if (owner !== this.owner()) throw new Error('Booking account changed')
      // The public topic endpoint reports OK/data:[]/total:0 to anonymous
      // clients. Do not cache that shell as a verified 30-minute catalogue.
      const publicEmpty: boolean = path === '/reservation/api/topic/resource-list' &&
        SportsBooking.total(body) === 0 && SportsBooking.venues(body).length === 0
      if (!publicEmpty) SportsBookingRepository.cache.set(key, { body, at: Date.now() });
      while (SportsBookingRepository.cache.size > 48) { const first: string | undefined = SportsBookingRepository.cache.keys().next().value; if (first !== undefined) SportsBookingRepository.cache.delete(first) }
      return body
    }).finally(() => { if (SportsBookingRepository.flights.get(key) === task) SportsBookingRepository.flights.delete(key) })
    SportsBookingRepository.flights.set(key, task); return task
  }
  async venues(force: boolean): Promise<BookingVenue[]> {
    const owner = this.owner(); const result: BookingVenue[] = []; let total = 1, received = 0
    for (let page: number = 1; received < total && page <= 30; page++) {
      const path: string = '/reservation/api/topic/resource-list', query: string = '?p=' + page + '&attr=%7B%7D&pageSize=100&id=48&hideTime=1&date='
      let body: string = await this.read(path, query, SportsBooking.TOPIC, force, 30 * 60000)
      let rows: BookingVenue[] = SportsBooking.venues(body)
      if (page === 1 && rows.length === 0 && SportsBooking.total(body) === 0) {
        // Unlike the public homepage/catalogue, this official iOS contact API
        // returns UN_AUTH without a real booking session. Confirm once; the
        // shared campus layer may silently redeem SSO, never present a page.
        await this.read('/reservation/site/user/detail-mobile', '', SportsBooking.TOPIC, true, 0)
        body = await this.read(path, query, SportsBooking.TOPIC, true, 30 * 60000)
        rows = SportsBooking.venues(body)
      }
      total = SportsBooking.total(body); received += rows.length
      for (const row of rows) if (!result.some((current: BookingVenue) => current.id === row.id)) result.push(row)
      if (rows.length === 0) { if (received < total) throw new Error('Booking venue catalogue is incomplete'); break }
    }
    if (owner !== this.owner()) throw new Error('Booking account changed')
    if (received < total) throw new Error('Booking venue catalogue exceeds the page limit')
    return result
  }
  async detail(id: number, force: boolean): Promise<BookingDetail> { return SportsBooking.detail(await this.read('/reservation/site/resource/detail', '?id=' + id, SportsBooking.page(id), force, 5 * 60000)) }
  async calendar(id: number, day: string, force: boolean): Promise<BookingCalendar> {
    const dates: BookingDateRange = { start_date: day, end_date: day }
    const range = JSON.stringify(dates)
    return SportsBooking.calendar(await this.read('/reservation/site/resource/calendar', '?resource_id=' + id + '&id=' + id + '&collective=0&date=' + encodeURIComponent(range), SportsBooking.page(id), force, 60000, false))
  }
  async appointments(page: number, force: boolean): Promise<BookingAppointments> { return SportsBooking.appointments(await this.read('/reservation/site/appointment/appointment-list', '?p=' + page + '&type=0&pageSize=20', SportsBooking.APPOINTMENTS, force), page) }
  async occupants(id: number, resources: number[], day: string, period: BookingPeriod, page: number): Promise<BookingOccupants> {
    const query: string = resources.map((value: number) => 'id%5B%5D=' + value).join('&') + '&date=' + day + '&period_id=' + period.id +
      '&start_time=' + encodeURIComponent(period.start_time) + '&end_time=' + encodeURIComponent(period.end_time) + '&page=' + page + '&pageSize=20'
    return SportsBooking.occupants(await this.read('/reservation/site/resource/reserve-info', '?' + query, SportsBooking.page(id)), page)
  }
  async contact(): Promise<BookingContact> { return SportsBooking.data<BookingContact>(await this.read('/reservation/site/user/detail-mobile', '', SportsBooking.TOPIC, false, 5 * 60000)) }
  private mutate(path: string, fields: Record<string, string>, referer: string): Promise<string> {
    const owner = this.owner(), key = owner + '/' + path + JSON.stringify(fields)
    const joined = SportsBookingRepository.mutations.get(key); if (joined !== undefined) return joined
    const task = FduRepository.getInstance().withService(SportsBooking.LOGIN, async (cookies: string): Promise<string> => {
      const headers = this.headers(path, 'POST', referer, true, cookies); headers['Origin'] = SportsBooking.ORIGIN
      const response = await HttpUtil.getInstance().postMultipart(SportsBooking.ORIGIN + path, fields, headers)
      SportsBooking.data<Object>(response.data); return response.data
    }, false).then((body: string): string => {
      if (owner !== this.owner()) throw new Error('Booking account changed')
      SportsBookingRepository.cache.clear(); return body
    }).finally(() => { if (SportsBookingRepository.mutations.get(key) === task) SportsBookingRepository.mutations.delete(key) })
    SportsBookingRepository.mutations.set(key, task); return task
  }
  async launch(value: BookingLaunch): Promise<BookingLaunchResult> { return SportsBooking.data<BookingLaunchResult>(await this.mutate('/reservation/site/resource/launch', SportsBooking.launchFields(value), SportsBooking.page(value.group))) }
  async cancel(id: number, details: number[]): Promise<void> {
    if (details.length === 0) throw new Error('No cancellable reservation details')
    const fields: Record<string, string> = {}; fields['appointment_id'] = String(id); fields['appointment_detail_id'] = JSON.stringify(details)
    await this.mutate('/reservation/site/appointment/appointment-cancel', fields, SportsBooking.APPOINTMENTS)
  }
  async verify(): Promise<void> { await FduRepository.getInstance().verifyService(SportsBooking.LOGIN) }
}
