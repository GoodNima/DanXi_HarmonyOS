import { Course, TimetableHelper } from './Academic'
import { TeachingCalendar } from './TeachingCalendar'
import { TimetableSchedule } from './TimetableSchedule'
import { parseObject, jsonArray } from './Forum'

/** Date-query contract retained in the upstream GraduateCourseAPI.swift. It
 * is a historical complement, not a replacement for the current course feed. */
export class GraduateHistory {
  static range(monday: string): Record<string, string> {
    if (!TeachingCalendar.validMonday(monday)) throw new Error('GraduateHistoryMondayInvalid')
    const end: Date = new Date(monday + 'T00:00:00'); end.setDate(end.getDate() + 20 * 7)
    const fields: Record<string, string> = {}
    fields['ksrq'] = monday; fields['jsrq'] = TeachingCalendar.iso(end); fields['ids'] = ''
    return fields
  }
  static parse(body: string, monday: string): Course[] {
    const root = parseObject(body)
    if (!Array.isArray(root['datas'])) throw new Error('GraduateHistoryDataInvalid: datas is not an array')
    const rows: Course[] = []
    const first: number = Date.parse(monday + 'T00:00:00Z')
    for (const raw of jsonArray(root, 'datas')) {
      const item: Record<string, Object> = raw as Record<string, Object>
      const begin: RegExpExecArray | null = /^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2})/.exec(String(item['KSSJ'] ?? ''))
      const title: string = typeof item['TITLE'] === 'string' ? item['TITLE'] as string : ''
      if (begin === null || !title) throw new Error('GraduateHistoryCourseFieldsInvalid')
      const day: number = Date.parse(begin[1] + 'T00:00:00Z')
      if (!Number.isFinite(day) || new Date(day).toISOString().slice(0, 10) !== begin[1]) throw new Error('GraduateHistoryDateInvalid')
      const week: number = Math.floor((day - first) / (7 * 86400000)) + 1
      if (day < first || week > 20) continue
      const unit: number = TimetableSchedule.UNITS.find((value: number) => TimetableHelper.getSlotStartTime(value) === begin[2]) ?? 0
      if (!unit) throw new Error('GraduateHistoryPeriodUnrecognised: ' + begin[2])
      const name: string = title.slice(title.indexOf('-') + 1).split('(')[0].trim()
      const codeMatch: RegExpExecArray | null = /\((?:\d{10})([^().]+)(?:\.\d+)?\)/.exec(title)
      const course: Course = { id: 'graduate-history-' + String(rows.length), name: name, code: codeMatch?.[1] ?? '',
        teachers: [], room: typeof item['DD'] === 'string' ? item['DD'] as string : '', weekday: ((new Date(day).getUTCDay() + 6) % 7) + 1,
        startUnit: unit, endUnit: unit, weekIndexes: [week] }
      if (!TimetableSchedule.valid(course)) throw new Error('GraduateHistoryCourseInvalid')
      rows.push(course)
    }
    const meetings: Course[] = TimetableSchedule.merge(rows)
    const courses: Course[] = []
    for (const meeting of meetings) {
      const existing: Course | undefined = courses.find((course: Course) => course.name === meeting.name && course.code === meeting.code &&
        course.room === meeting.room && course.weekday === meeting.weekday && course.startUnit === meeting.startUnit && course.endUnit === meeting.endUnit)
      if (existing !== undefined) existing.weekIndexes = Array.from(new Set<number>(existing.weekIndexes.concat(meeting.weekIndexes))).sort((a: number, b: number) => a - b)
      else courses.push(meeting)
    }
    return courses
  }
}
