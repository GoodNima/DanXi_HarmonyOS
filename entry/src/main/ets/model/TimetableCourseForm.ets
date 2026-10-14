import { Course } from './Academic'
import { TimetableSchedule } from './TimetableSchedule'

export interface CourseFormValues {
  name: string
  teacher: string
  location: string
  code: string
  weekday: number
  firstUnit: string
  lastUnit: string
  weeks: string
}

export enum CourseFormIssue {
  NONE = 0,
  NAME = 1,
  WEEKDAY = 2,
  FIRST_UNIT = 3,
  LAST_UNIT = 4,
  UNIT_ORDER = 5,
  WEEKS = 6
}

/** Keep unfilled text distinct from actual course numbers. Editing copies the
 * existing meeting instead of silently replacing its periods or week mask. */
export class TimetableCourseForm {
  static draft(course?: Course): CourseFormValues {
    return {
      name: course?.name ?? '',
      teacher: course?.teachers.join(' / ') ?? '',
      location: course?.room ?? '',
      code: course?.code ?? '',
      weekday: course?.weekday ?? 0,
      firstUnit: course ? String(course.startUnit) : '',
      lastUnit: course ? String(course.endUnit) : '',
      weeks: course?.weekIndexes.join(',') ?? ''
    }
  }

  private static unit(value: string): number {
    const text = value.trim()
    return /^\d{1,2}$/.test(text) ? Number(text) : 0
  }

  private static weekText(value: string): string {
    return value.trim().replace(/\s*([-，,])\s*/g, '$1')
  }

  static issue(value: CourseFormValues): CourseFormIssue {
    if (!value.name.trim()) return CourseFormIssue.NAME
    if (!Number.isInteger(value.weekday) || value.weekday < 1 || value.weekday > 7) return CourseFormIssue.WEEKDAY
    const first = TimetableCourseForm.unit(value.firstUnit)
    const last = TimetableCourseForm.unit(value.lastUnit)
    if (first < 1 || first > 15) return CourseFormIssue.FIRST_UNIT
    if (last < 1 || last > 15) return CourseFormIssue.LAST_UNIT
    if (last < first) return CourseFormIssue.UNIT_ORDER
    if (!TimetableSchedule.weeks(TimetableCourseForm.weekText(value.weeks)).length) return CourseFormIssue.WEEKS
    return CourseFormIssue.NONE
  }

  static course(value: CourseFormValues, id: string): Course | undefined {
    if (TimetableCourseForm.issue(value) !== CourseFormIssue.NONE) return undefined
    return {
      id: id, name: value.name.trim(), teachers: value.teacher.trim() ? [value.teacher.trim()] : [],
      room: value.location.trim(), code: value.code.trim(), weekday: value.weekday,
      startUnit: TimetableCourseForm.unit(value.firstUnit), endUnit: TimetableCourseForm.unit(value.lastUnit),
      weekIndexes: TimetableSchedule.weeks(TimetableCourseForm.weekText(value.weeks))
    }
  }
}
