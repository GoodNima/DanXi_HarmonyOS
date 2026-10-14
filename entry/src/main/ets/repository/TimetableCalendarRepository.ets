import { calendarManager } from '@kit.CalendarKit'
import { abilityAccessCtrl, common } from '@kit.AbilityKit'
import { Course } from '../model/Academic'
import { CourseCalendarEvent, TimetableCalendar } from '../model/TimetableCalendar'
import { AppLanguage } from '../common/AppLanguage'

export interface CalendarExportResult { total: number; added: number; updated: number; unchanged: number }

/** Only an app-owned calendar is read or changed. A failed partial write is
 * safely resumable: the next read discovers the successfully written IDs. */
export class TimetableCalendarRepository {
  private static flights: Map<string, Promise<CalendarExportResult>> = new Map<string, Promise<CalendarExportResult>>()

  static account(owner: string, monday: string): calendarManager.CalendarAccount {
    // Avoid exposing a student identifier in the system calendar's account name.
    let hash: number = 2166136261
    for (let i: number = 0; i < owner.length; i++) hash = Math.imul(hash ^ owner.charCodeAt(i), 16777619) >>> 0
    return { name: 'danxi-courses-' + hash.toString(16) + '-' + monday,
      type: calendarManager.CalendarType.LOCAL,
      displayName: AppLanguage.text($r('app.string.timetable_calendar_name'), 0, monday) }
  }

  static async export(context: common.UIAbilityContext, owner: string, courses: Course[], monday: string): Promise<CalendarExportResult> {
    const events: CourseCalendarEvent[] = TimetableCalendar.events(courses, monday)
    if (events.length === 0) throw new Error(AppLanguage.text($r('app.string.timetable_export_empty')))
    const key: string = owner + '/' + monday
    const pending: Promise<CalendarExportResult> | undefined = TimetableCalendarRepository.flights.get(key)
    if (pending !== undefined) return pending
    const task: Promise<CalendarExportResult> = TimetableCalendarRepository.write(context, owner, events, monday)
    TimetableCalendarRepository.flights.set(key, task)
    try { return await task } finally { if (TimetableCalendarRepository.flights.get(key) === task) TimetableCalendarRepository.flights.delete(key) }
  }

  private static async write(context: common.UIAbilityContext, owner: string, events: CourseCalendarEvent[], monday: string): Promise<CalendarExportResult> {
    const permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context,
      ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR'])
    if (permission.authResults.length !== 2 || permission.authResults.some((result: number) => result !== 0)) {
      throw new Error(AppLanguage.text($r('app.string.timetable_calendar_permission_denied')) + ' (CalendarPermissionDenied)')
    }
    const manager: calendarManager.CalendarManager = calendarManager.getCalendarManager(context)
    const account: calendarManager.CalendarAccount = TimetableCalendarRepository.account(owner, monday)
    const calendars: calendarManager.Calendar[] = await manager.getAllCalendars()
    let calendar: calendarManager.Calendar | undefined = calendars.find((item: calendarManager.Calendar) =>
      item.getAccount().name === account.name && item.getAccount().type === account.type)
    if (calendar === undefined) {
      calendar = await manager.createCalendar(account)
      await calendar.setConfig({ color: '#3578BA', enableReminder: false })
    }
    return TimetableCalendarRepository.sync(calendar, events)
  }

  static async sync(calendar: calendarManager.Calendar, planned: CourseCalendarEvent[]): Promise<CalendarExportResult> {
    // The native overload rejects an explicit undefined filter. On API 20+
    // the zero-argument form includes identifiers and all fields used below.
    const existing: calendarManager.Event[] = await calendar.getEvents()
    const result: CalendarExportResult = { total: planned.length, added: 0, updated: 0, unchanged: 0 }
    for (const plan of planned) {
      const previous: calendarManager.Event | undefined = existing.find((item: calendarManager.Event) => item.identifier === plan.identifier)
      const event: calendarManager.Event = { type: calendarManager.EventType.NORMAL, title: plan.title,
        description: plan.description, location: { location: plan.location }, startTime: plan.startTime, endTime: plan.endTime,
        timeZone: 'Asia/Shanghai', identifier: plan.identifier, isAllDay: false }
      if (previous?.id !== undefined) {
        if (previous.title === event.title && previous.description === event.description &&
          previous.location?.location === plan.location && previous.startTime === event.startTime && previous.endTime === event.endTime) {
          result.unchanged++
        } else { event.id = previous.id; await calendar.updateEvent(event); result.updated++ }
      } else {
        const id: number = await calendar.addEvent(event)
        if (!Number.isInteger(id) || id <= 0) throw new Error('CalendarWriteReturnedInvalidId')
        event.id = id; existing.push(event); result.added++
      }
    }
    // Only retire the old meetings of courses explicitly selected this time.
    // Other courses and all user-created events in this calendar are preserved.
    const groups: string[] = Array.from(new Set<string>(planned.map((item: CourseCalendarEvent) => item.group)))
    const identities: Set<string> = new Set<string>(planned.map((item: CourseCalendarEvent) => item.identifier))
    const retired: number[] = existing.filter((item: calendarManager.Event) => item.id !== undefined &&
      item.identifier !== undefined && groups.some((group: string) => item.identifier!.startsWith(group)) &&
      !identities.has(item.identifier)).map((item: calendarManager.Event) => item.id!)
    if (retired.length > 0) await calendar.deleteEvents(retired)
    return result
  }
}
