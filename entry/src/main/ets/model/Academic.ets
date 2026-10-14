/**
 * Campus / academic models.
 *
 * ── Why these shapes look the way they do ──
 *
 * This file used to declare interfaces nobody had ever observed on the wire: a
 * `BusSchedule.remainingSeats`, an `ExamSchedule.seat`, a `GPASummary.totalCredit`
 * with a `semesterGPA` map. Nothing in the Fudan services returns those, and the
 * values rendered from them were invented. Every shape below is now transcribed
 * from the upstream Dart models that really decode these endpoints, and the
 * numbers were thrown away in favour of the raw display strings the server
 * actually sends — see the rule below.
 *
 * Rule (inherited from model/Card.ets:7-11): keep server display text as
 * `string`. Converting to `number` invents precision the server never promised
 * and throws on one odd row, losing the whole page instead of one field. A
 * missing value stays `''` (or the literal the server sent), never a made-up 0.
 */

/**
 * Upstream `enum BusDirection { NONE, DUAL, BACKWARD, FORWARD }`
 * (lib/repository/fdu/bus_repository.dart:119-128). The ordinal is what the
 * server's `arrow` field carries, so the values are load-bearing.
 */
export enum BusDirection {
  NONE = 0,
  DUAL = 1,
  BACKWARD = 2,
  FORWARD = 3,
}

/**
 * Arrow glyph for a bus direction. Upstream keeps these as display constants
 * (lib/repository/fdu/bus_repository.dart:131-133) and has none for NONE, which
 * is why the fallback is this port's own separator rather than upstream text.
 */
export function busDirectionArrow(direction: BusDirection): string {
  if (direction === BusDirection.FORWARD) {
    return ' → '
  }
  if (direction === BusDirection.BACKWARD) {
    return ' ← '
  }
  if (direction === BusDirection.DUAL) {
    return ' ↔ '
  }
  return ' — '
}

/**
 * One scheduled bus departure.
 *
 * Upstream `BusScheduleItem` (lib/repository/fdu/bus_repository.dart:63-72).
 * Note what is NOT here: a line name and a remaining-seat count. The upstream
 * repository flattens every route's `lists` into one array and keeps neither
 * the route object nor any seat figure — the bus endpoint is a timetable, not
 * an availability query. `startCampus`/`endCampus` are the Chinese campus names
 * the server sends (邯郸/枫林/江湾/张江); an unrecognised name stays `''`.
 *
 * `startTime`/`endTime` are `HH:mm` or `''`. Upstream parses `stime`/`etime`
 * with `replaceAll(".", ":")` because the server writes `08.30`, and drops any
 * row where BOTH are empty (bus_repository.dart:55, :88-93).
 */
export interface BusSchedule {
  id: string
  startCampus: string
  endCampus: string
  startTime: string
  endTime: string
  direction: BusDirection
  holidayRun: boolean
}

/**
 * Dormitory electricity, as the dorm endpoint reports it.
 *
 * Upstream `ElectricityItem` (lib/repository/fdu/dorm_repository.dart:61-69).
 * All five fields are strings because the server sends them as display text.
 * `dormName` is the server's own concatenation `xq + ssmc + fjmc` (campus +
 * building + room), reproduced verbatim rather than reassembled here.
 */
export interface ElectricityInfo {
  available: string
  used: string
  updateTime: string
  roomId: string
  dormName: string
}

/**
 * One row of the department GPA/rank table.
 *
 * Upstream `GpaListItem` (lib/repository/fdu/edu_service_repository.dart:626-634).
 *
 * There is deliberately no overall GPA and no credit-weighted average: the
 * Fudan endpoint returns a RANKING TABLE (one row per major within a
 * department), and upstream DanXi never computes a GPA of its own — the number
 * it shows is the server's `gpa` string, unmodified. An earlier version of this
 * port declared a `GPASummary { gpa, totalCredit, semesterGPA }`, which
 * described data the endpoint never sends. LocalGpa now separately calculates
 * a scoped result from real CourseGrade records, without changing this model.
 */
export interface GpaListItem {
  name: string
  id: string
  gpa: string
  credits: string
  rank: string
  year: string
  major: string
  college: string
}

/**
 * One exam, decoded from the exam-arrange HTML table.
 *
 * Upstream `Exam` (lib/repository/fdu/edu_service_repository.dart:378-397).
 * `type` is the exam kind (期末/期中) and `testCategory` is the parenthesised
 * course category. There is no seat number and no duration anywhere in the
 * upstream model: the third `<span>` of the first cell is the room, which
 * upstream calls `location`.
 */
export interface ExamSchedule {
  id: string
  name: string
  type: string
  date: string
  time: string
  location: string
  testCategory: string
  note: string
}

/**
 * One course grade, decoded from the grade-sheet JSON.
 *
 * Upstream `ExamScore` (lib/repository/fdu/edu_service_repository.dart:525-533).
 * `gradePoint` is `''` when the course has no GP (pass/no-pass courses), which
 * upstream models as a nullable `String?` and the server omits.
 *
 * Preserve credits only when the endpoint supplies them. Missing values remain
 * absent/empty and are excluded from local GPA calculation; never infer credits
 * or convert the upstream literal "null" into a number.
 */
export interface CourseGrade {
  credit?: string
  courseId: string
  courseName: string
  type: string
  level: string
  gradePoint: string
  semester: string
}

/**
 * A semester and the Monday its week 1 starts on.
 *
 * Upstream keeps these in `SemesterInfo` + `TimeTableStartDateItem`
 * (lib/repository/fdu/edu_service_repository.dart:262-265, lib/model/extra.dart:23-27).
 * The `startDate` the server publishes is a SUNDAY and upstream adds one day
 * (time_table_repository.dart:151-154); that adjustment is applied at parse
 * time, so this field is already the Monday. It is `''` when unknown.
 */
export interface SemesterInfo {
  id: string
  name: string
  startDate: string
  /** Published last day, without the start-date Monday adjustment. */
  endDate?: string
}

/**
 * One course activity from the timetable print-data payload.
 *
 * Upstream `Course.fromJWGLJson` (lib/model/time_table.dart:302-320). Units and
 * weekdays are kept 1-based exactly as the server sends them, and `weekday`
 * follows the server's numbering (1 = Monday) so it lines up with
 * `TimetableHelper.getTodayWeekday()`.
 */
export interface Course {
  id: string
  code: string
  name: string
  teachers: string[]
  room: string
  weekday: number
  startUnit: number
  endUnit: number
  weekIndexes: number[]
}

export interface CourseReview {
  id: number
  courseId: string
  courseName: string
  author: string
  content: string
  rating: number
  likes: number
  timeCreated: string
}

/**
 * A classroom row parsed from the campus LAN or authenticated WebVPN backend.
 */
export interface EmptyClassroom {
  building: string
  room: string
  capacity: number
  status: string
  campus: string
  roomId?: string
  day?: string
  /** One-based free slots and the real usage text of the first 13 slots. */
  freePeriods?: number[]
  periods?: string[]
}

export interface Announcement {
  id: string
  title: string
  source: string
  content: string
  publishTime: string
  url: string
  category: string
}

/**
 * A timetable row ready to render.
 *
 * Upstream builds these per (course, weekday, slot) — `Course.fromJWGLJson`
 * emits one `CourseTime` for every slot in `startUnit..endUnit` inclusive
 * (lib/model/time_table.dart:306-310). `weeks` carries the server's 1-based
 * `weekIndexes` unchanged. `color` is presentation only and derived
 * deterministically from the course name, so it is stable across renders
 * without being data.
 */
export interface TimeTableEntry {
  courseName: string
  teacher: string
  location: string
  weekday: number
  startSection: number
  endSection: number
  weeks: number[]
  color: string
}

export class TimetableHelper {
  /**
   * Upstream `kCourseSlotStartTime` (lib/model/time_table.dart:87-103) — 15
   * periods, not 12, and the gaps differ from the previous ported table (which
   * was a different university's bell schedule).
   */
  static readonly SLOT_START_TIMES: string[] = [
    '08:00', '08:55', '09:55', '10:50', '11:45',
    '13:30', '14:25', '15:25', '16:20', '17:15',
    '18:30', '19:25', '20:20', '21:15', '22:10',
  ]

  /** Upstream `TimeTable.MAX_WEEK` (lib/model/time_table.dart:84). */
  static readonly MAX_WEEK: number = 18

  /** Start time of a 1-based period, or `''` when out of range. */
  static getSlotStartTime(unit: number): string {
    if (unit >= 1 && unit <= TimetableHelper.SLOT_START_TIMES.length) {
      return TimetableHelper.SLOT_START_TIMES[unit - 1]
    }
    return ''
  }

  /** Monday = 1 .. Sunday = 7, matching the server's `weekday` field. */
  static getTodayWeekday(): number {
    const day = new Date().getDay()
    return day === 0 ? 7 : day
  }

  /**
   * Which teaching week `now` falls in, given the Monday that week 1 starts on.
   *
   * Upstream `TimeTable.now()` (lib/model/time_table.dart:161-182) returns
   * `diff.inDays ~/ 7 + 1`. Returns 0 when the start date is unknown or `now`
   * is before the semester — upstream yields a non-positive week in that case,
   * which matches no course, so 0 keeps the same behaviour while being honest
   * about the fact that there is no week.
   */
  static weekOf(startDateIso: string, now: Date): number {
    if (startDateIso.length === 0) {
      return 0
    }
    const startMs: number = Date.parse(startDateIso + 'T00:00:00')
    if (isNaN(startMs)) {
      return 0
    }
    const diffMs: number = now.getTime() - startMs
    if (diffMs < 0) {
      return 0
    }
    const weekMs: number = 7 * 24 * 60 * 60 * 1000
    return Math.floor(diffMs / weekMs) + 1
  }
}
