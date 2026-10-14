import { HttpResponse, HttpUtil } from '../util/HttpUtil'
import { EmptyClassroom } from '../model/Academic'
import { parseObjectArray, jsonString } from '../model/Forum'

interface ClassroomCacheEntry { rooms: EmptyClassroom[]; expires: number }
interface ClassroomFlight { forceRefresh: boolean; promise: Promise<EmptyClassroom[]> }

/** Upstream empty_classroom_repository.dart and WebVPNInterceptor. */
export class ClassroomRepository {
  static readonly BUILDINGS: string[] = ['HGD', 'HGX', 'H2', 'H3', 'H4', 'H5', 'H6', 'HQ', 'F', 'J', 'Z', 'F1', 'F2', 'JA', 'JB', 'Z2']
  static readonly LOGIN_URL: string = 'https://webvpn.fudan.edu.cn/login?cas_login=true'
  static readonly DIRECT: string = 'http://10.64.130.6'
  // Fixed public host translation from upstream AES-CFB algorithm, not a session credential.
  static readonly WEBVPN: string = 'https://webvpn.fudan.edu.cn/http/77726476706e69737468656265737421a1a70fca737e39032e46df'

  private static readonly CACHE_LIFETIME: number = 30000
  private static readonly CACHE_LIMIT: number = 24
  private static cache: Map<string, ClassroomCacheEntry> = new Map<string, ClassroomCacheEntry>()
  private static flights: Map<string, ClassroomFlight> = new Map<string, ClassroomFlight>()
  private static context: string = ''
  private static generation: number = 0

  /** Account/session scope is supplied by FduRepository and never persisted. */
  static invalidate(): void {
    ClassroomRepository.generation++
    ClassroomRepository.cache.clear()
    ClassroomRepository.flights.clear()
    ClassroomRepository.context = ''
  }

  static dayString(day: string = ''): string {
    const now: Date = new Date()
    const value: string = day || String(now.getFullYear()) + '-' +
      String(now.getMonth() + 1).padStart(2, '0') + '-' + String(now.getDate()).padStart(2, '0')
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error('请选择有效查询日期')
    const parsed: Date = new Date(value + 'T12:00:00')
    if (!Number.isFinite(parsed.getTime()) || parsed.getFullYear() !== Number(value.substring(0, 4)) ||
      parsed.getMonth() + 1 !== Number(value.substring(5, 7)) || parsed.getDate() !== Number(value.substring(8, 10))) {
      throw new Error('请选择有效查询日期')
    }
    return value
  }

  static async cached(building: string, day: string, context: string, forceRefresh: boolean,
    loader: () => Promise<EmptyClassroom[]>): Promise<EmptyClassroom[]> {
    if (!ClassroomRepository.BUILDINGS.includes(building)) throw new Error('请选择有效教学楼')
    if (context !== ClassroomRepository.context) {
      ClassroomRepository.invalidate()
      ClassroomRepository.context = context
    }
    const key: string = building + ':' + ClassroomRepository.dayString(day)
    const pending: ClassroomFlight | undefined = ClassroomRepository.flights.get(key)
    // Refresh supersedes an ordinary in-flight load; another refresh shares that fresh load.
    if (pending !== undefined && (!forceRefresh || pending.forceRefresh)) {
      return ClassroomRepository.copy(await pending.promise)
    }
    const cached: ClassroomCacheEntry | undefined = ClassroomRepository.cache.get(key)
    if (!forceRefresh && cached !== undefined && cached.expires > Date.now()) {
      ClassroomRepository.cache.delete(key)
      ClassroomRepository.cache.set(key, cached)
      return ClassroomRepository.copy(cached.rooms)
    }
    const flight: ClassroomFlight = { forceRefresh: forceRefresh, promise: Promise.resolve<EmptyClassroom[]>([]) }
    flight.promise = ClassroomRepository.loadCached(key, flight, ClassroomRepository.generation, loader)
    ClassroomRepository.flights.set(key, flight)
    return ClassroomRepository.copy(await flight.promise)
  }

  private static async loadCached(key: string, flight: ClassroomFlight, generation: number,
    loader: () => Promise<EmptyClassroom[]>): Promise<EmptyClassroom[]> {
    // Register the flight before invoking a loader that can throw synchronously.
    await Promise.resolve()
    try {
      const rooms: EmptyClassroom[] = await loader()
      if (generation !== ClassroomRepository.generation) throw new Error('校园账号或会话已切换，请重新加载')
      // An older response must not overwrite a newer forced refresh.
      if (ClassroomRepository.flights.get(key) === flight) {
        const now: number = Date.now()
        const expired: string[] = []
        ClassroomRepository.cache.forEach((value: ClassroomCacheEntry, name: string) => {
          if (value.expires <= now) expired.push(name)
        })
        for (const name of expired) ClassroomRepository.cache.delete(name)
        ClassroomRepository.cache.delete(key)
        ClassroomRepository.cache.set(key, { rooms: ClassroomRepository.copy(rooms), expires: now + ClassroomRepository.CACHE_LIFETIME })
        while (ClassroomRepository.cache.size > ClassroomRepository.CACHE_LIMIT) {
          const keys: string[] = []
          ClassroomRepository.cache.forEach((value: ClassroomCacheEntry, name: string) => keys.push(name))
          if (keys.length === 0) break
          ClassroomRepository.cache.delete(keys[0])
        }
      }
      return rooms
    } finally {
      if (ClassroomRepository.flights.get(key) === flight) ClassroomRepository.flights.delete(key)
    }
  }

  private static copy(rooms: EmptyClassroom[]): EmptyClassroom[] {
    return rooms.map((row: EmptyClassroom): EmptyClassroom => ({
      building: row.building, room: row.room, capacity: row.capacity, status: row.status, campus: row.campus,
      roomId: row.roomId, day: row.day, freePeriods: row.freePeriods?.slice(), periods: row.periods?.slice()
    }))
  }

  static async load(building: string, cookies: string = '', selectedDay: string = ''): Promise<EmptyClassroom[]> {
    if (!ClassroomRepository.BUILDINGS.includes(building)) throw new Error('请选择有效教学楼')
    const day: string = ClassroomRepository.dayString(selectedDay)
    const base = cookies ? ClassroomRepository.WEBVPN : ClassroomRepository.DIRECT
    const headers: Record<string, string> = { 'User-Agent': HttpUtil.BROWSER_UA }
    if (cookies) headers['Cookie'] = cookies
    const query = '?b=' + encodeURIComponent(building) + '&day=' + day
    const http = HttpUtil.getInstance()
    const responses: HttpResponse[] = await Promise.all<HttpResponse>([
      http.get(base + '/daystatus.asp' + query, undefined, headers, cookies ? 15000 : 3000),
      http.get(base + '/' + query + '&c=&p=', undefined, headers, cookies ? 15000 : 3000)
    ])
    return ClassroomRepository.parse(responses[0].data, responses[1].data, building, day)
  }

  static parse(status: string, html: string, building: string, day: string = ''): EmptyClassroom[] {
    const match = /"status"\s*:\s*(\[[\s\S]*?\])/.exec(status)
    if (match === null) throw new Error('未取得空教室数据，请检查校园网或重新登录 WebVPN')
    const rooms = parseObjectArray(match[1])
    const result: EmptyClassroom[] = []
    for (let i = 0; i < rooms.length; i++) {
      const id = jsonString(rooms[i], 'id')
      const name = jsonString(rooms[i], 'room')
      if (!id || !name) continue
      const start = html.indexOf('"c' + id + '"')
      const nextId = i + 1 < rooms.length ? jsonString(rooms[i + 1], 'id') : ''
      const end = nextId ? html.indexOf('"r' + nextId + '"', start + 1) : html.indexOf('innerHTML', start + 1)
      if (start < 0) throw new Error('空教室页面结构变化，请稍后重试')
      const row = html.substring(start, end >= 0 ? end : html.length)
      const capacity = />(\d+)</.exec(row)
      const cells = /<td\b[^>]*style\s*=\s*["'][^"']*background-color[^"']*["'][^>]*>([\s\S]*?)<\/td>/gi
      const free: number[] = []
      const periods: string[] = []
      let period = 0
      let cell: RegExpExecArray | null = cells.exec(row)
      while (cell !== null && period < 13) {
        period++
        const content = cell[1].replace(/<[^>]*>/g, '').replace(/&nbsp;|&#160;/gi, ' ').trim()
        periods.push(content)
        if (!content) free.push(period)
        cell = cells.exec(row)
      }
      if (period !== 13) throw new Error('空教室课节数据不完整，请稍后重试')
      result.push({ building: building, room: name, capacity: capacity ? Number(capacity[1]) : 0,
        campus: building.startsWith('H') ? '邯郸' : building.startsWith('F') ? '枫林' : building.startsWith('J') ? '江湾' : '张江',
        status: free.length > 0 ? '空闲课节：' + free.join('、') : '今日课节均占用',
        roomId: id, day: day, freePeriods: free, periods: periods })
    }
    return result
  }
}
