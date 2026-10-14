import { Course, TimetableHelper } from './Academic'
import { TeachingCalendar } from './TeachingCalendar'

export interface ScheduleEdits { added: Course[]; hidden: string[] }

export class TimetableSchedule {
  static readonly DAYS: number[] = [1, 2, 3, 4, 5, 6, 7]
  static readonly UNITS: number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
  static readonly COLORS: string[] = ['#3578BA', '#387C54', '#97651D', '#7952A4', '#A04D76', '#277F85']

  static key(course: Course): string {
    return JSON.stringify([course.code, course.name, course.teachers, course.room, course.weekday,
      course.startUnit, course.endUnit, course.weekIndexes])
  }

  static valid(course: Course): boolean {
    return typeof course.name === 'string' && course.name.trim().length > 0 &&
      Array.isArray(course.teachers) && Array.isArray(course.weekIndexes) &&
      Number.isInteger(course.weekday) && course.weekday >= 1 && course.weekday <= 7 &&
      Number.isInteger(course.startUnit) && course.startUnit >= 1 &&
      Number.isInteger(course.endUnit) && course.endUnit >= course.startUnit && course.endUnit <= 15 &&
      course.weekIndexes.length > 0 && course.weekIndexes.every((week: number) => Number.isInteger(week) && week >= 1 && week <= 30)
  }

  /** Graduate endpoints report consecutive periods separately. Merge only when
   * all observed identity, room, weekday and week-mask fields agree. */
  static merge(courses: Course[]): Course[] {
    const sorted = courses.filter((course: Course) => TimetableSchedule.valid(course))
      .map((course: Course): Course => ({ id: course.id, code: course.code, name: course.name,
        teachers: course.teachers.slice(), room: course.room, weekday: course.weekday,
        startUnit: course.startUnit, endUnit: course.endUnit, weekIndexes: course.weekIndexes.slice().sort((a: number, b: number) => a - b) }))
      .sort((a: Course, b: Course) => a.weekday - b.weekday || a.startUnit - b.startUnit)
    const result: Course[] = []
    for (const course of sorted) {
      const previous = result.find((row: Course) => row.weekday === course.weekday && row.name === course.name &&
        row.code === course.code && row.room === course.room && row.teachers.join('|') === course.teachers.join('|') &&
        row.weekIndexes.join(',') === course.weekIndexes.join(',') && row.endUnit + 1 === course.startUnit)
      if (previous) previous.endUnit = course.endUnit
      else if (!result.some((row: Course) => TimetableSchedule.key(row) === TimetableSchedule.key(course))) result.push(course)
    }
    return result
  }

  static display(official: Course[], edits: ScheduleEdits): Course[] {
    const seen: Set<string> = new Set<string>()
    return official.filter((course: Course) => !edits.hidden.includes(TimetableSchedule.key(course)))
      .concat(edits.added.filter((course: Course) => TimetableSchedule.valid(course)))
      .filter((course: Course): boolean => {
        const key: string = TimetableSchedule.key(course)
        if (seen.has(key)) return false
        seen.add(key)
        return true
      })
  }

  static weeks(value: string): number[] {
    if (!/^\d+(?:-\d+)?(?:[,，]\d+(?:-\d+)?)*$/.test(value.trim())) return []
    const result: number[] = []
    for (const range of value.trim().replace(/，/g, ',').split(',')) {
      const bounds = range.split('-')
      const first = Number(bounds[0]), last = Number(bounds[bounds.length - 1])
      if (first < 1 || last > 30 || first > last) return []
      for (let week = first; week <= last; week++) if (!result.includes(week)) result.push(week)
    }
    return result.sort((a: number, b: number) => a - b)
  }

  static color(course: Course): string {
    let hash = 0
    for (let i = 0; i < course.name.length; i++) hash = (hash * 31 + course.name.charCodeAt(i)) | 0
    return TimetableSchedule.COLORS[Math.abs(hash) % TimetableSchedule.COLORS.length]
  }

  static lane(course: Course, rows: Course[]): number {
    const ends: number[] = []
    for (const row of rows) {
      let lane = ends.findIndex((end: number) => end < row.startUnit)
      if (lane < 0) { lane = ends.length; ends.push(row.endUnit) } else ends[lane] = row.endUnit
      if (TimetableSchedule.key(row) === TimetableSchedule.key(course)) return lane
    }
    return 0
  }

  static laneCount(rows: Course[]): number {
    const ends: number[] = []
    for (const row of rows) {
      const lane = ends.findIndex((end: number) => end < row.startUnit)
      if (lane < 0) ends.push(row.endUnit)
      else ends[lane] = row.endUnit
    }
    return Math.max(1, ends.length)
  }

  static day(start: string, week: number, weekday: number): Date {
    const date = new Date(start + 'T00:00:00')
    date.setDate(date.getDate() + (week - 1) * 7 + weekday - 1)
    return date
  }

  static endTime(unit: number): string {
    const parts = TimetableHelper.getSlotStartTime(unit).split(':')
    if (parts.length !== 2) return ''
    const total = Number(parts[0]) * 60 + Number(parts[1]) + 45
    return String(Math.floor(total / 60)).padStart(2, '0') + ':' + String(total % 60).padStart(2, '0')
  }

  private static escape(value: string): string {
    return value.replace(/\\/g, '\\\\').replace(/\r?\n/g, '\\n').replace(/;/g, '\\;').replace(/,/g, '\\,')
  }

  /** UTF-8 RFC5545 physical lines, at most 75 octets, including continuation space. */
  private static fold(value: string): string {
    let line = '', result = '', bytes = 0
    for (const ch of value) {
      const point = ch.codePointAt(0) ?? 0
      const size = point < 0x80 ? 1 : point < 0x800 ? 2 : point < 0x10000 ? 3 : 4
      if (bytes + size > 75) { result += line + '\r\n'; line = ' '; bytes = 1 }
      line += ch; bytes += size
    }
    return result + line
  }

  static ics(courses: Course[], start: string, now: Date = new Date()): string {
    if (!TeachingCalendar.validMonday(start)) throw new Error('Missing semester Monday')
    const stamp = now.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z')
    const lines: string[] = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//DanXi//Timetable//ZH', 'CALSCALE:GREGORIAN']
    const seen: string[] = []
    for (const course of courses.filter((row: Course) => TimetableSchedule.valid(row))) {
      for (const week of course.weekIndexes) {
        const key = TimetableSchedule.key(course) + ':' + String(week)
        if (seen.includes(key)) continue
        seen.push(key)
        const date = TimetableSchedule.day(start, week, course.weekday)
        // UTC event times are universally interoperable. Fudan uses UTC+8,
        // independent of the timezone selected on the user's device.
        const first = TimetableHelper.getSlotStartTime(course.startUnit).split(':')
        const last = TimetableSchedule.endTime(course.endUnit).split(':')
        const begin = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate(), Number(first[0]) - 8, Number(first[1])))
        const end = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate(), Number(last[0]) - 8, Number(last[1])))
        const uid = 'danxi-' + encodeURIComponent(key + ':' + start) + '@local'
        lines.push('BEGIN:VEVENT', 'UID:' + uid,
          'DTSTAMP:' + stamp, 'DTSTART:' + begin.toISOString().replace(/[-:]/g, '').replace('.000Z', 'Z'),
          'DTEND:' + end.toISOString().replace(/[-:]/g, '').replace('.000Z', 'Z'),
          'SUMMARY:' + TimetableSchedule.escape(course.name), 'LOCATION:' + TimetableSchedule.escape(course.room),
          'DESCRIPTION:' + TimetableSchedule.escape(course.teachers.join(' / ') + '\n' + course.code), 'END:VEVENT')
      }
    }
    lines.push('END:VCALENDAR')
    return lines.map((line: string) => TimetableSchedule.fold(line)).join('\r\n') + '\r\n'
  }
}
