import { CampusHtml, CampusHtmlNode } from './CampusHtml'
import { EmptyClassroom } from './Academic'
import { parseObjectArray, jsonString } from './Forum'
import { FduAuthPolicy } from './FduAuth'
import { HttpError } from '../util/HttpUtil'

export class ClassroomSchedule {
  start: number = 1
  end: number = 1
  name: string = ''
  courseId: string = ''
  teacher: string = ''
  category: string = ''
  enrollment: string = ''
}
export class ScheduledClassroom {
  room: string = ''
  roomId: string = ''
  capacity: number = 0
  building: string = ''
  day: string = ''
  periodCount: number = 13
  schedules: ClassroomSchedule[] = []
  freePeriods: number[] = []
}
class ClassroomColumns {
  capacity: number = 1
  periods: number[] = []
}
export class ClassroomScheduleParser {
  static readonly BUILDINGS: string[] = ['H2', 'H3', 'H4', 'H5', 'H6', 'HGX', 'HGD', 'HQ', 'J', 'F', 'Z']
  static normalizeBuilding(value: string): string {
    return ['F1', 'F2'].includes(value) ? 'F' : ['JA', 'JB'].includes(value) ? 'J' : value === 'Z2' ? 'Z' : value
  }
  static campus(building: string): string { return building.startsWith('F') ? '枫林' : building.startsWith('J') ? '江湾' : building.startsWith('Z') ? '张江' : '邯郸' }
  static preview(rooms: ScheduledClassroom[]): EmptyClassroom[] {
    return rooms.map((room: ScheduledClassroom): EmptyClassroom => {
      const periods: string[] = []
      for (let index: number = 1; index <= room.periodCount; index++) {
        periods.push(room.schedules.find((item: ClassroomSchedule) => item.start <= index && item.end >= index)?.name ?? '')
      }
      return { room: room.room, roomId: room.roomId,
      capacity: room.capacity, campus: ClassroomScheduleParser.campus(room.building), building: room.building, day: room.day,
      status: '', freePeriods: room.freePeriods.slice(), periods: periods }
    })
  }
  static parse(html: string, building: string, day: string): ScheduledClassroom[] {
    if (html.length > 4 * 1024 * 1024) throw new Error('Classroom schedule response is too large')
    if (FduAuthPolicy.isLoginDocument(html)) throw new HttpError(-2, 0, '教室日程需要校园 WebVPN 身份验证，请点击继续验证。', '')
    const table: CampusHtmlNode | undefined = CampusHtml.parse(html).findId('statusTable_0')
    if (table === undefined) throw new Error('Classroom schedule table statusTable_0 is missing')
    const columns: ClassroomColumns = ClassroomScheduleParser.columns(table)
    const result: ScheduledClassroom[] = []
    for (const row of table.rows()) {
      const cells: CampusHtmlNode[] = row.direct('td')
      if (cells.length < 3) continue
      const anchor: CampusHtmlNode | undefined = ClassroomScheduleParser.find(cells[0], 'a')
      if (anchor === undefined || !anchor.orderedText()) continue
      const label: string = anchor.orderedText()
      // The three upstream header rows can contain numeric spans as well as
      // anchors. A numeric neighbour does not turn their labels into a room.
      if (['教室', '座位', '座位数', '节次', '容量'].includes(label) ||
        (/^\d{1,2}$/.test(label) && !/^rt\d+$/.test(anchor.attributes['id'] ?? ''))) continue
      // The ASP header uses anchors too (including the “座位” column).
      // Identify a room by its numeric capacity, never by an anchor alone.
      const expanded: CampusHtmlNode[] = ClassroomScheduleParser.expand(cells)
      const capacity: string = ClassroomScheduleParser.capacity(expanded[columns.capacity] ?? cells[1])
      if (!capacity) continue
      // Match iOS's actual returned columns. Different buildings serve 13,
      // 14 or 15 periods; truncating at 13 loses real late-evening courses.
      const lessons: CampusHtmlNode[] = ClassroomScheduleParser.lessons(cells, columns)
      const periods: number = lessons.length
      if (periods < 13 || periods > 15) throw new Error('Classroom schedule has incomplete periods: ' + anchor.orderedText() + ' (' + periods + ')')
      const room = new ScheduledClassroom(); room.room = anchor.orderedText(); room.roomId = anchor.attributes['id'] || room.room
      room.building = building; room.day = day
      room.periodCount = periods
      room.capacity = Number(capacity)
      ClassroomScheduleParser.periods(room, lessons)
      result.push(room)
    }
    return result
  }
  /** The ASP has three header rows with rowspan/colspan. Read the numbered
   * lesson columns rather than counting every td after the second column.
   * Seat/equipment columns remain metadata regardless of their wording. */
  private static columns(table: CampusHtmlNode | undefined): ClassroomColumns {
    const result: ClassroomColumns = new ClassroomColumns()
    if (table === undefined) return result
    const occupied: number[] = []
    for (const row of table.rows().slice(0, 3)) {
      if (ClassroomScheduleParser.find(row, 'a')?.attributes['id']?.startsWith('rt')) break
      for (let index: number = 0; index < occupied.length; index++) occupied[index] = Math.max(0, occupied[index] - 1)
      let column: number = 0
      const numbered: Map<number, number> = new Map<number, number>()
      for (const cell of row.children.filter((node: CampusHtmlNode): boolean => node.tag === 'td' || node.tag === 'th')) {
        while ((occupied[column] ?? 0) > 0) column++
        const span: number = ClassroomScheduleParser.span(cell, 'colspan')
        const rows: number = ClassroomScheduleParser.span(cell, 'rowspan')
        const label: string = cell.orderedText().replace(/\s/g, '')
        if (column > 0 && /^(?:座位(?:数)?|容量)$/.test(label)) result.capacity = column
        const period: RegExpExecArray | null = /^(?:第)?(\d{1,2})(?:节(?:次)?)?$/.exec(label)
        if (span === 1 && period !== null && Number(period[1]) >= 1 && Number(period[1]) <= 15) numbered.set(Number(period[1]), column)
        for (let offset: number = 0; offset < span; offset++) occupied[column + offset] = rows
        column += span
      }
      if (numbered.size >= 13 && numbered.size <= 15) {
        const periods: number[] = []
        for (let unit: number = 1; unit <= numbered.size; unit++) {
          const position: number | undefined = numbered.get(unit)
          if (position === undefined) break
          periods.push(position)
        }
        // Number-only header rows can omit the room/capacity rowspan cells.
        // Their local positions then overlap metadata, so they cannot define
        // the classroom row's period offsets. Use iOS's two-column boundary.
        if (periods.length === numbered.size && periods[0] > result.capacity) result.periods = periods
      }
    }
    return result
  }
  private static span(cell: CampusHtmlNode, attribute: string): number {
    const value: number = Number(cell.attributes[attribute] ?? '1')
    return Number.isInteger(value) && value >= 1 && value <= 30 ? value : 1
  }
  private static expand(cells: CampusHtmlNode[]): CampusHtmlNode[] {
    const expanded: CampusHtmlNode[] = []
    for (const cell of cells) {
      for (let offset: number = 0; offset < ClassroomScheduleParser.span(cell, 'colspan'); offset++) expanded.push(cell)
    }
    return expanded
  }
  private static lessons(cells: CampusHtmlNode[], columns: ClassroomColumns, fragment: boolean = false): CampusHtmlNode[] {
    if (columns.periods.length > 0) {
      const expanded: CampusHtmlNode[] = ClassroomScheduleParser.expand(cells)
      const offset: number = fragment ? columns.capacity + 1 : 0
      // Some cached ASP headers show 13 periods while their room data already
      // returns 14/15. Preserve the actual contiguous lesson range, including
      // late courses and legacy leading capacity labels absent from the header.
      const first: number = columns.periods[0]
      const contiguous: boolean = columns.periods.every((column: number, index: number): boolean => column === first + index)
      if (contiguous) return ClassroomScheduleParser.lessonCells(expanded.slice(first - offset))
      // Non-contiguous numbered columns explicitly identify metadata gaps.
      const lessons: CampusHtmlNode[] = []
      for (const column of columns.periods) {
        const cell: CampusHtmlNode | undefined = expanded[column - offset]
        if (cell === undefined) break
        lessons.push(cell)
      }
      return lessons
    }
    return ClassroomScheduleParser.lessonCells(ClassroomScheduleParser.expand(fragment ? cells : cells.slice(2)))
  }
  private static capacity(cell: CampusHtmlNode): string {
    const match: RegExpExecArray | null = /^(?:座位\s*[:：]?\s*)?(\d+)\s*(?:座位|座|人)?$/.exec(cell.orderedText())
    if (match !== null) return match[1]
    for (const child of cell.children) {
      const value: string = ClassroomScheduleParser.capacity(child)
      if (value) return value
    }
    return ''
  }
  /** Capacity-only script literals sometimes repeat a seat/equipment label
   * before the lesson cells. Remove only that leading metadata, retaining
   * each nested table as one cell and never truncating real evening lessons. */
  private static lessonCells(cells: CampusHtmlNode[]): CampusHtmlNode[] {
    let start: number = 0
    while (start < cells.length) {
      const text: string = cells[start].orderedText()
      const label: string = text.replace(/[\s:：()（）]/g, '')
      if (/^(?:座位(?:数)?(?:\d+(?:个|座|人)?)?|\d+(?:个)?座位)$/.test(label) || (text.startsWith('座位') &&
        ClassroomScheduleParser.find(cells[start], 'table') !== undefined && !text.includes('['))) start++
      else break
    }
    return cells.slice(start)
  }
  private static periods(room: ScheduledClassroom, rawCells: CampusHtmlNode[]): void {
      const cells: CampusHtmlNode[] = rawCells
      if (cells.length < 13 || cells.length > 15) throw new Error('Classroom schedule has incomplete periods: ' + room.room + ' (' + cells.length + ')')
      room.periodCount = cells.length
      let previous: ClassroomSchedule | undefined = undefined
      for (let index: number = 0; index < cells.length; index++) {
        const cell: CampusHtmlNode = cells[index]
        const text: string = cell.orderedTextWithoutSpans()
        if (!text) { room.freePeriods.push(index + 1); previous = undefined; continue }
        const schedule: ClassroomSchedule = ClassroomScheduleParser.schedule(cell, index + 1)
        if (previous !== undefined && previous.end === schedule.start - 1 && previous.name === schedule.name &&
          previous.courseId === schedule.courseId && previous.teacher === schedule.teacher && previous.category === schedule.category) previous.end = schedule.end
        else { room.schedules.push(schedule); previous = schedule }
      }
  }
  static needsStatus(html: string): boolean {
    return /["']c\d+["'][\s\S]*?<td\b[^>]*background-color/i.test(html) && /innerHTML/.test(html)
  }
  /** The date-aware ASP page also emits rows inside JavaScript string data.
   * Read only literal cells (as the Android client does); never execute scripts
   * or mistake the empty pre-script statusTable_0 shell for an empty day. */
  static fromStatus(html: string, status: string, building: string, day: string): ScheduledClassroom[] {
    if (html.length > 4 * 1024 * 1024 || status.length > 4 * 1024 * 1024) throw new Error('Classroom schedule response is too large')
    const match: RegExpExecArray | null = /"status"\s*:\s*(\[[\s\S]*?\])/.exec(status)
    if (match === null) throw new Error('Classroom status array is missing')
    const rooms = parseObjectArray(match[1]), result: ScheduledClassroom[] = []
    const columns: ClassroomColumns = ClassroomScheduleParser.columns(CampusHtml.parse(html).findId('statusTable_0'))
    const literals: Map<string, string> = ClassroomScheduleParser.literalRows(html)
    for (let index: number = 0; index < rooms.length; index++) {
      const id: string = jsonString(rooms[index], 'id'), name: string = jsonString(rooms[index], 'room')
      if (!id || !name) throw new Error('Classroom identity is missing')
      const fragment: string | undefined = literals.get(id)
      if (fragment === undefined) throw new Error('Classroom literal row is missing: ' + id)
      // A capacity cell may contain a nested table with a “座位” label. Only
      // direct cells of the actual classroom row are periods; matching every
      // styled td flattens that table and shifts all lessons by one period.
      const literal: CampusHtmlNode | undefined = CampusHtml.parse(fragment).findId('r' + id)
      if (literal !== undefined) {
        const cells: CampusHtmlNode[] = literal.direct('td')
        if (cells.length < 3) throw new Error('Classroom literal row is incomplete: ' + name)
        const room = new ScheduledClassroom()
        room.room = name; room.roomId = id; room.building = building; room.day = day
        const expanded: CampusHtmlNode[] = ClassroomScheduleParser.expand(cells)
        const seats: string = ClassroomScheduleParser.capacity(expanded[columns.capacity] ?? cells[1])
        if (!seats) throw new Error('Classroom capacity is missing: ' + name)
        room.capacity = Number(seats)
        ClassroomScheduleParser.periods(room, ClassroomScheduleParser.lessons(cells, columns)); result.push(room); continue
      }
      const capacity: RegExpExecArray | null = />(\d+)</.exec(fragment)
      // Some date literals retain a complete capacity td; others start inside
      // it. Only the latter can use all direct tds as lessons. Compare the
      // first opening td with the known capacity value before selecting periods.
      const room = new ScheduledClassroom()
      room.room = name; room.roomId = id; room.building = building; room.day = day
      room.capacity = Number(capacity?.[1] ?? '0')
      const lessons: CampusHtmlNode[] = ClassroomScheduleParser.lessons(ClassroomScheduleParser.literalCells(fragment, capacity), columns, true)
      if (lessons.length < 13 || lessons.length > 15) throw new Error('Classroom literal periods are incomplete: ' + name + ' (' + lessons.length + ')')
      ClassroomScheduleParser.periods(room, lessons)
      result.push(room)
    }
    return result
  }
  private static literalCells(fragment: string, capacity: RegExpExecArray | null): CampusHtmlNode[] {
    const cells: CampusHtmlNode[] = CampusHtml.parse(fragment).direct('td')
    const opening: number = fragment.search(/<td\b/i)
    // A real first-period course may also have a numeric code. Exclude the
    // first cell only when it encloses the capacity already preceding lessons,
    // contains that scalar value alone, and is therefore room metadata.
    if (capacity !== null && opening >= 0 && opening < capacity.index && cells.length > 0 &&
      cells[0].orderedText() === capacity[1]) return cells.slice(1)
    return cells
  }
  /** The status response can order rooms differently from the page. Bound a
   * literal by the next actual row/capacity marker in that same document, not
   * by a status-array neighbour that may occur before it or be absent. Index
   * the document once so a building never rescans all subsequent rooms. */
  private static literalRows(html: string): Map<string, string> {
    const rows: Map<string, string> = new Map()
    const pattern: RegExp = /["']([rc])(\d+)["']/g
    let marker: RegExpExecArray | null = pattern.exec(html)
    let id: string = '', start: number = -1
    while (marker !== null) {
      // A script may name c81 before writing a whole capacity cell that also
      // contains id="c81". That attribute is still inside the same literal;
      // treating it as a new boundary truncates the seat value and all lessons.
      const tagStart: number = html.lastIndexOf('<', marker.index)
      if (marker[1] === 'c' && marker[2] === id && tagStart > html.lastIndexOf('>', marker.index) &&
        /^<(?:td|span)\b/i.test(html.substring(tagStart, marker.index))) {
        marker = pattern.exec(html); continue
      }
      if (start >= 0) ClassroomScheduleParser.keepLiteral(rows, id, html.substring(start, marker.index))
      if (marker[1] === 'r') {
        // Include the opening tr so its direct columns retain their nesting.
        const opening: number = html.lastIndexOf('<tr', marker.index)
        if (opening >= 0 && html.indexOf('>', opening) > marker.index) {
          const next = /<tr\b[^>]*\bid\s*=\s*["']r\d+["']/g
          next.lastIndex = marker.index + marker[0].length
          const following: RegExpExecArray | null = next.exec(html)
          const end: number = following?.index ?? html.indexOf('innerHTML', marker.index)
          rows.set(marker[2], html.substring(opening, end > opening ? end : html.length))
        }
      }
      id = marker[1] === 'c' ? marker[2] : ''
      start = id ? marker.index : -1
      marker = pattern.exec(html)
    }
    if (start >= 0) {
      const end: number = html.indexOf('innerHTML', start + 1)
      ClassroomScheduleParser.keepLiteral(rows, id, html.substring(start, end > start ? end : html.length))
    }
    return rows
  }
  private static keepLiteral(rows: Map<string, string>, id: string, fragment: string): void {
    const previous: string | undefined = rows.get(id)
    // A getElementById reference is not a row of literal cells. Preserve the
    // first actual row when later scripts reference the same capacity element.
    if (previous === undefined || (!/<tr\b[^>]*\bid\s*=/i.test(previous) && !/<td\b[^>]*background-color/i.test(previous))) rows.set(id, fragment)
  }
  private static find(node: CampusHtmlNode, tag: string, className: string = ''): CampusHtmlNode | undefined {
    if (node.tag === tag && (!className || (node.attributes['class'] ?? '').split(/\s+/).includes(className))) return node
    for (const child of node.children) { const found = ClassroomScheduleParser.find(child, tag, className); if (found !== undefined) return found }
    return undefined
  }
  private static schedule(cell: CampusHtmlNode, slot: number): ClassroomSchedule {
    const item = new ClassroomSchedule(); item.start = slot; item.end = slot
    item.category = ClassroomScheduleParser.find(cell, 'span', 'rare')?.orderedText() ??
      ClassroomScheduleParser.find(cell, 'span', 'tag')?.orderedText() ?? ''
    let text: string = cell.orderedTextWithoutSpans()
    text = text.replace(/\s*\.\s*/g, '.')
    const code: RegExpExecArray | null = /^([A-Za-z0-9]+(?:\.[A-Za-z0-9]+)?)\s*/.exec(text)
    if (code !== null) { item.courseId = code[1]; text = text.substring(code[0].length).trim() }
    const course: RegExpExecArray | null = /\[([^\]]+)\](?:\(([^)]+)\))?(?:\{([^}]+)\})?/.exec(text)
    item.name = course?.[1] ?? text; item.teacher = course?.[2] ?? ''; item.enrollment = course?.[3] ?? ''
    if (!item.name) item.name = cell.orderedText()
    return item
  }
  static search(rooms: ScheduledClassroom[], query: string): ScheduledClassroom[] {
    const text: string = query.trim().toLocaleLowerCase()
    return text ? rooms.filter((room: ScheduledClassroom) => room.room.toLocaleLowerCase().includes(text) ||
      room.schedules.some((event: ClassroomSchedule) => [event.name, event.courseId, event.teacher].some((value: string) => value.toLocaleLowerCase().includes(text)))) : rooms
  }
}
