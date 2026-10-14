import { ClassroomScheduleParser, ScheduledClassroom } from '../model/ClassroomSchedule'
import { ClassroomRepository } from './ClassroomRepository'
import { HttpUtil } from '../util/HttpUtil'
import { FduRepository } from './FduRepository'
import { AppState } from '../common/AppState'
import { CampusCookies } from '../common/CampusCookies'
import { Constant } from '../common/Constant'

interface ClassroomDayCache { rooms: ScheduledClassroom[]; at: number }
export interface ClassroomScheduleSource {
  owner(): string
  read(building: string, day: string, force: boolean): Promise<ScheduledClassroom[]>
  verify(): Promise<void>
}
/** Parse the iOS static schedule when present; use the Android date-aware
 * literal rows only when the page requires them. Search stays local. */
export class ClassroomScheduleRepository {
  private static cache: Map<string, ClassroomDayCache> = new Map()
  private static flights: Map<string, Promise<ScheduledClassroom[]>> = new Map()
  static owner(): string { return AppState.getPerson().getStudentId() + '/' + String(AppState.isLoggedIn()) + '/' + CampusCookies.generation() }
  static async read(building: string, day: string, force: boolean = false, authorized: boolean = true): Promise<ScheduledClassroom[]> {
    building = ClassroomScheduleParser.normalizeBuilding(building)
    if (!ClassroomScheduleParser.BUILDINGS.includes(building)) throw new Error('Invalid classroom building')
    day = ClassroomRepository.dayString(day)
    const owner: string = ClassroomScheduleRepository.owner(), key: string = owner + '/' + building + '/' + day
    const cached = ClassroomScheduleRepository.cache.get(key)
    if (!force && cached !== undefined && Date.now() - cached.at < 120000) return cached.rooms
    const flightKey: string = key + '/' + authorized
    const flight = ClassroomScheduleRepository.flights.get(flightKey)
    if (flight !== undefined) return flight
    const task: Promise<ScheduledClassroom[]> = ClassroomScheduleRepository.fetch(building, day, authorized).then((rooms: ScheduledClassroom[]): ScheduledClassroom[] => {
      if (owner !== ClassroomScheduleRepository.owner()) throw new Error('Classroom account changed')
      ClassroomScheduleRepository.cache.set(key, { rooms: rooms, at: Date.now() })
      while (ClassroomScheduleRepository.cache.size > 24) { const first: string | undefined = ClassroomScheduleRepository.cache.keys().next().value; if (first !== undefined) ClassroomScheduleRepository.cache.delete(first) }
      return rooms
    }).finally(() => { if (ClassroomScheduleRepository.flights.get(flightKey) === task) ClassroomScheduleRepository.flights.delete(flightKey) })
    ClassroomScheduleRepository.flights.set(flightKey, task); return task
  }
  private static async fetch(building: string, day: string, authorized: boolean): Promise<ScheduledClassroom[]> {
    const fdu = FduRepository.getInstance()
    const useVpn: boolean = AppStorage.get<boolean>(Constant.KEY_USE_WEBVPN) !== false
    const load = async (cookies: string): Promise<ScheduledClassroom[]> => {
      const url: string = cookies ? ClassroomRepository.WEBVPN : ClassroomRepository.DIRECT
      const http = HttpUtil.getInstance()
      const headers: Record<string, string> = { 'User-Agent': HttpUtil.BROWSER_UA, 'Cookie': cookies, 'Accept': 'text/html' }
      const timeout: number = cookies ? 15000 : 3000
      const response = await http.get(url + '/', { 'b': building, 'c': '', 'p': '', 'day': day }, headers, timeout)
      let rooms: ScheduledClassroom[] = []
      try { rooms = ClassroomScheduleParser.parse(response.data, building, day) }
      catch (e) {
        if (!ClassroomScheduleParser.needsStatus(response.data) || (e as Error).message !== 'Classroom schedule table statusTable_0 is missing') throw e as Error
      }
      if (!ClassroomScheduleParser.needsStatus(response.data)) return rooms
      const status = await http.get(url + '/daystatus.asp', { 'b': building, 'day': day }, headers, timeout)
      return ClassroomScheduleParser.fromStatus(response.data, status.data, building, day)
    }
    if (!useVpn) return load('')
    if (!authorized) {
      const cookies: string = fdu.cookiesFor(ClassroomRepository.LOGIN_URL)
      // The LAN endpoint still works without a WebVPN session. A passive read
      // has a short budget and cannot open an authentication page.
      return load(cookies)
    }
    return fdu.withService(ClassroomRepository.LOGIN_URL, load)
  }
}
export class DefaultClassroomScheduleSource implements ClassroomScheduleSource {
  owner(): string { return ClassroomScheduleRepository.owner() }
  read(building: string, day: string, force: boolean): Promise<ScheduledClassroom[]> { return ClassroomScheduleRepository.read(building, day, force) }
  async verify(): Promise<void> { await FduRepository.getInstance().verifyService(ClassroomRepository.LOGIN_URL) }
}
