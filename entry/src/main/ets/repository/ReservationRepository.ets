import { Playground, ReservationSlot, ReservationParser } from '../model/Reservation'
import { FduRepository } from './FduRepository'
import { HttpUtil, HttpError } from '../util/HttpUtil'
import { CampusService } from '../common/CampusService'
import { CampusCookies } from '../common/CampusCookies'
import { AppState } from '../common/AppState'
import { TeachingCalendar } from '../model/TeachingCalendar'

interface CatalogCache { items: Playground[]; updatedAt: number }
interface SlotsCache { items: ReservationSlot[]; updatedAt: number }
export interface ReservationDocumentReader { read(url: string): Promise<string> }
export class CallbackReservationDocumentReader implements ReservationDocumentReader {
  private callback: (url: string) => Promise<string>
  constructor(callback: (url: string) => Promise<string>) { this.callback = callback }
  read(url: string): Promise<string> { return this.callback(url) }
}

/** Read-only lookups are coalesced; bookings are submitted by the university's
 * own form in the shared WebView cookie jar, matching the iOS flow. */
export class ReservationRepository {
  private static catalog: Map<string, CatalogCache> = new Map<string, CatalogCache>()
  private static catalogFlights: Map<string, Promise<Playground[]>> = new Map<string, Promise<Playground[]>>()
  private static slotsCache: Map<string, SlotsCache> = new Map<string, SlotsCache>()
  private static slotsFlights: Map<string, Promise<ReservationSlot[]>> = new Map<string, Promise<ReservationSlot[]>>()
  private static browserOwners: Set<string> = new Set<string>()

  static owner(): string { return AppState.getPerson().getStudentId() + '/' + String(AppState.isLoggedIn()) + '/' + String(CampusCookies.generation()) }
  static cached(): Playground[] | undefined { return ReservationRepository.catalog.get(ReservationRepository.owner())?.items.slice() }

  static async playgrounds(force: boolean = false, reader?: ReservationDocumentReader): Promise<Playground[]> {
    const owner: string = ReservationRepository.owner()
    const cached: CatalogCache | undefined = ReservationRepository.catalog.get(owner)
    if (!force && cached !== undefined && Date.now() - cached.updatedAt < 30 * 60000) return cached.items.slice()
    const flight: Promise<Playground[]> | undefined = ReservationRepository.catalogFlights.get(owner)
    if (flight !== undefined) return flight
    const task: Promise<Playground[]> = FduRepository.getInstance().withService(CampusService.RESERVATION,
      async (cookies: string): Promise<Playground[]> => {
        const items: Playground[] = []
        for (const category of ReservationParser.CATEGORIES) {
          const body: string = await ReservationRepository.document('/public/front/search.htm',
            { 'id': category, 'pageBean.pageSize': '100' }, cookies, owner, reader)
          items.push(...ReservationParser.playgrounds(body, category))
        }
        if (owner !== ReservationRepository.owner()) throw new Error('ReservationAccountChanged')
        const unique: Playground[] = items.filter((item: Playground, index: number) => items.findIndex((row: Playground) => row.id === item.id) === index)
        ReservationRepository.catalog.set(owner, { items: unique, updatedAt: Date.now() })
        if (ReservationRepository.catalog.size > 4) {
          const first: string | undefined = ReservationRepository.catalog.keys().next().value
          if (first !== undefined) ReservationRepository.catalog.delete(first)
        }
        return unique
      }).finally(() => { if (ReservationRepository.catalogFlights.get(owner) === task) ReservationRepository.catalogFlights.delete(owner) })
    ReservationRepository.catalogFlights.set(owner, task)
    return task
  }

  static async slots(place: Playground, date: string, force: boolean = false, reader?: ReservationDocumentReader): Promise<ReservationSlot[]> {
    if (!/^[A-Za-z0-9]+$/.test(place.id) || !/^\d{4}-\d{2}-\d{2}$/.test(date) ||
      !Number.isFinite(Date.parse(date + 'T00:00:00')) || TeachingCalendar.iso(new Date(date + 'T00:00:00')) !== date) {
      throw new Error('InvalidReservationQuery')
    }
    const owner: string = ReservationRepository.owner()
    const key: string = owner + '/' + place.id + '/' + date
    const cached: SlotsCache | undefined = ReservationRepository.slotsCache.get(key)
    if (!force && cached !== undefined && Date.now() - cached.updatedAt < 60000) return cached.items.slice()
    const flight: Promise<ReservationSlot[]> | undefined = ReservationRepository.slotsFlights.get(key)
    if (flight !== undefined) return flight
    const task: Promise<ReservationSlot[]> = FduRepository.getInstance().withService(CampusService.RESERVATION,
      async (cookies: string): Promise<ReservationSlot[]> => {
        const params: Record<string, string> = {}
        params['contentId'] = place.id; params['currentDate'] = date
        const body: string = await ReservationRepository.document('/public/front/getResource2.htm', params, cookies, owner, reader)
        const items: ReservationSlot[] = ReservationParser.slots(body, place, date)
        if (owner !== ReservationRepository.owner()) throw new Error('ReservationAccountChanged')
        ReservationRepository.slotsCache.set(key, { items: items, updatedAt: Date.now() })
        while (ReservationRepository.slotsCache.size > 32) {
          const first: string | undefined = ReservationRepository.slotsCache.keys().next().value
          if (first !== undefined) ReservationRepository.slotsCache.delete(first)
        }
        return items
      }).finally(() => { if (ReservationRepository.slotsFlights.get(key) === task) ReservationRepository.slotsFlights.delete(key) })
    ReservationRepository.slotsFlights.set(key, task)
    return task
  }
  private static headers(cookies: string): Record<string, string> {
    return { 'Cookie': cookies, 'Accept': 'text/html,application/xhtml+xml', 'Content-Type': '', 'Authorization': '',
      'Referer': ReservationParser.ORIGIN + '/', 'User-Agent': HttpUtil.BROWSER_UA }
  }
  private static async document(path: string, params: Record<string, string>, cookies: string, owner: string,
    reader?: ReservationDocumentReader): Promise<string> {
    const url: string = ReservationParser.ORIGIN + path
    const browserUrl: string = url + '?' + Object.keys(params).map((key: string) => encodeURIComponent(key) + '=' + encodeURIComponent(params[key])).join('&')
    if (reader !== undefined && ReservationRepository.browserOwners.has(owner)) return reader.read(browserUrl)
    try { return (await HttpUtil.getInstance().get(url, params, ReservationRepository.headers(cookies), 15000)).data }
    catch (e) {
      // HTTP 412 is a site precondition/security response, not an invalid CAS
      // password. Let the university's own browser execute its checks once.
      // Do not renew identity, clear cookies, or repeatedly replay the failing GET.
      if (!(e instanceof HttpError) || e.statusCode !== 412 || reader === undefined) throw e as Error
      ReservationRepository.browserOwners.add(owner)
      while (ReservationRepository.browserOwners.size > 4) {
        const first: string | undefined = ReservationRepository.browserOwners.values().next().value
        if (first !== undefined) ReservationRepository.browserOwners.delete(first)
      }
      return reader.read(browserUrl)
    }
  }
}

export interface ReservationSource {
  owner(): string
  playgrounds(force: boolean): Promise<Playground[]>
  slots(place: Playground, date: string, force: boolean): Promise<ReservationSlot[]>
  verify(): Promise<void>
}
export class DefaultReservationSource implements ReservationSource {
  private reader: ReservationDocumentReader | undefined = undefined
  setDocumentReader(reader: ReservationDocumentReader): void { this.reader = reader }
  owner(): string { return ReservationRepository.owner() }
  playgrounds(force: boolean): Promise<Playground[]> { return ReservationRepository.playgrounds(force, this.reader) }
  slots(place: Playground, date: string, force: boolean): Promise<ReservationSlot[]> { return ReservationRepository.slots(place, date, force, this.reader) }
  async verify(): Promise<void> { await FduRepository.getInstance().verifyService(CampusService.RESERVATION) }
}
