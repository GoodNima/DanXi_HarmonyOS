import { Course, TimetableHelper } from './Academic'
import { TimetableSchedule } from './TimetableSchedule'
import { TeachingCalendar } from './TeachingCalendar'

export interface CourseCalendarEvent {
  identifier: string
  group: string
  title: string
  description: string
  location: string
  startTime: number
  endTime: number
}

/** All timestamps describe the campus's UTC+8 wall clock, including on devices
 * configured to another time zone. Identity excludes mutable room/teacher text. */
export class TimetableCalendar {
  static group(course: Course): string { return JSON.stringify([course.code, course.name]) }
  static events(courses: Course[], monday: string): CourseCalendarEvent[] {
    if (!TeachingCalendar.validMonday(monday)) throw new Error('CalendarSemesterMondayInvalid')
    const events: CourseCalendarEvent[] = []
    const seen: Set<string> = new Set<string>()
    for (const course of courses) {
      if (!TimetableSchedule.valid(course)) throw new Error('CalendarCourseInvalid')
      const group: string = 'danxi:' + monday + ':' + TimetableCalendar.group(course) + ':'
      for (const week of course.weekIndexes) {
        const identifier: string = group + JSON.stringify([week, course.weekday, course.startUnit, course.endUnit])
        if (seen.has(identifier)) continue
        if (identifier.length > 5000 || course.name.length > 5000 || course.room.length > 5000) throw new Error('CalendarEventTextTooLong')
        seen.add(identifier)
        const date: Date = TimetableSchedule.day(monday, week, course.weekday)
        const first: string[] = TimetableHelper.getSlotStartTime(course.startUnit).split(':')
        const last: string[] = TimetableSchedule.endTime(course.endUnit).split(':')
        const start: number = Date.UTC(date.getFullYear(), date.getMonth(), date.getDate(), Number(first[0]) - 8, Number(first[1]))
        const end: number = Date.UTC(date.getFullYear(), date.getMonth(), date.getDate(), Number(last[0]) - 8, Number(last[1]))
        if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) throw new Error('CalendarEventTimeInvalid')
        events.push({ identifier: identifier, group: group, title: course.name, location: course.room,
          description: [course.code, course.teachers.join(' / ')].filter((text: string) => text.length > 0).join('\n'),
          startTime: start, endTime: end })
      }
    }
    return events.sort((a: CourseCalendarEvent, b: CourseCalendarEvent) => a.startTime - b.startTime)
  }
}
