/**
 * fdjwgl.fudan.edu.cn — 课表 / 考试安排 / 成绩与 GPA / 课程列表.
 *
 * ── What the upstream app actually does ──
 *
 * Four capabilities, six endpoints, all GET, all behind the same CAS session:
 *
 *   course-table                          HTML, carries `var semesters = JSON.parse(...)`
 *   course-table/semester/{id}/print-data JSON, carries the student id + activities
 *   exam-arrange/info/{studentId}         HTML table
 *   grade/my-gpa/search-index/{id}        HTML, two hidden inputs
 *   grade/my-gpa/search?…                 JSON ranking table
 *   grade/sheet/info/{id}?semester=…      JSON, all semesters keyed by id
 *
 * Every one of them needs the *internal* student id, which is NOT the student
 * number: it is `studentTableVms[0].id` from print-data
 * (lib/repository/fdu/edu_service_repository.dart:67-95). Upstream types it as
 * `int` on purpose, "to fail fast if backend changes the schema" (:85-87).
 *
 * ── HTML parsing without BeautifulSoup ──
 *
 * Upstream uses `beautiful_soup_dart` with CSS selectors; ArkTS has no such
 * library, so the selectors are re-expressed as regular expressions. Regexes
 * built from HTML are fragile in general, and the mitigations here are the
 * house ones: the expressions are as tight as the real markup allows (the
 * exam rows in the fixture come from upstream's own quoted sample markup at
 * edu_service_repository.dart:412-458), anything that fails to match is
 * DROPPED rather than emitted half-empty, and a page that yields nothing at all
 * raises instead of rendering as "no exams". A shape change therefore shows up
 * as an error, which is the behaviour this codebase requires.
 *
 * ── Honesty note ──
 *
 * Parsers are faithful ports and are unit-tested against fixtures transcribed
 * from upstream's documented shapes. The LIVE responses have not been observed,
 * because that needs a real Fudan ID session. So the session guard throws
 * before any request, and none of this may be called "verified against the live
 * service" until someone runs it with an account.
 */

import { BaseRepository } from './BaseRepository'
import { HttpResponse, HttpError } from '../util/HttpUtil'
import { AppLanguage } from '../common/AppLanguage'
import {
  Course, CourseGrade, ExamSchedule, GpaListItem, SemesterInfo, TimeTableEntry,
} from '../model/Academic'

/**
 * Upstream `Constant.defaultUserAgent`, mobile branch
 * (lib/common/constant.dart:71-72) — the value the Flutter app really sent.
 */
const MOBILE_UA: string =
  'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/145.0.0.0 Mobile Safari/537.36'

/** The two hidden inputs the GPA flow reads (edu_service_repository.dart:167-182). */
export interface GpaSearchParams {
  grade: string
  departmentAssoc: string
}

// Locally-declared response shapes. Fields are `Object` where the payload is
// loose, and `undefined` where a key may simply be absent.
interface SemesterJson {
  id?: Object
  name?: Object
  startDate?: Object
  endDate?: Object
}

interface PrintEnvelope {
  studentTableVms?: PrintVm[]
}

interface PrintVm {
  id?: Object
  activities?: ActivityJson[]
}

interface ActivityJson {
  lessonId?: Object
  lessonCode?: Object
  courseName?: Object
  teachers?: Object[]
  room?: Object
  weekday?: Object
  startUnit?: Object
  endUnit?: Object
  weekIndexes?: Object[]
}

interface GpaEnvelope {
  data?: GpaRowJson[]
}

interface GpaRowJson {
  name?: Object
  code?: Object
  gpa?: Object
  credit?: Object
  ranking?: Object
  grade?: Object
  major?: Object
  department?: Object
}

interface GradeEnvelope {
  semesterId2studentGrades?: Record<string, GradeRowJson[]>
}

interface GradeRowJson {
  credits?: Object
  credit?: Object
  lessonCode?: Object
  courseCode?: Object
  courseName?: Object
  courseNameEn?: Object
  courseModuleTypeName?: Object
  courseType?: Object
  gaGrade?: Object
  gp?: Object
}

interface SemesterFlight { forceRefresh: boolean; promise: Promise<void> }

export class JwglRepository extends BaseRepository {
  static readonly HOST: string = 'https://fdjwgl.fudan.edu.cn'

  /** Upstream TIMETABLE_URL (lib/repository/fdu/time_table_repository.dart:35-36). */
  static readonly COURSE_TABLE_URL: string =
    'https://fdjwgl.fudan.edu.cn/student/for-std/course-table'

  /** Upstream TIMETABLE_DATA_URL, `{sem_id}` substituted (:33-34). */
  static readonly PRINT_DATA_URL: string =
    'https://fdjwgl.fudan.edu.cn/student/for-std/course-table/semester/'

  /** Upstream getExamArrangeUrl (edu_service_repository.dart:35-36). */
  static readonly EXAM_URL: string =
    'https://fdjwgl.fudan.edu.cn/student/for-std/exam-arrange/info/'

  /** Upstream getMyGpaSearchIndexUrl (:41-42). */
  static readonly GPA_INDEX_URL: string =
    'https://fdjwgl.fudan.edu.cn/student/for-std/grade/my-gpa/search-index/'

  /** Upstream getMyGpaSearchUrl (:44-49). `majorAssoc` is deliberately empty. */
  static readonly GPA_SEARCH_URL: string =
    'https://fdjwgl.fudan.edu.cn/student/for-std/grade/my-gpa/search'

  /** Upstream getGradeSheetUrl (:38-39). */
  static readonly GRADE_SHEET_URL: string =
    'https://fdjwgl.fudan.edu.cn/student/for-std/grade/sheet/info/'

  /**
   * Palette for the timetable colour bar. Presentation only: picked from the
   * course name so a course keeps one colour across renders. Upstream derives
   * its colours from the course's own theme; this port has no such source, so
   * it does not pretend to.
   */
  private static readonly PALETTE: string[] = [
    '#4A90D9', '#5BA85B', '#D98B4A', '#9B6BD9',
    '#D95B8B', '#4AA8A8', '#C0A03C', '#7A7AD9',
  ]

  private static instance: JwglRepository | null = null

  /** Session cookie string for fdjwgl.fudan.edu.cn; in memory only. */
  private campusCookies: string = ''

  // Resolved once per session: both are stable for the life of a login, and
  // re-deriving them costs two extra round trips per feature.
  private studentId: string = ''
  private semester: SemesterInfo | null = null
  private semesterRows: SemesterInfo[] = []
  private sessionVersion: number = 0
  private semesterGeneration: number = 0
  private semesterFlight: SemesterFlight | null = null
  private studentFlight: Promise<string> | null = null

  private constructor() {
    super()
  }

  static getInstance(): JwglRepository {
    if (!JwglRepository.instance) {
      JwglRepository.instance = new JwglRepository()
    }
    return JwglRepository.instance
  }

  setSession(cookies: string): void {
    if (this.campusCookies !== cookies) this.forgetSession()
    this.campusCookies = cookies
  }

  hasSession(): boolean {
    return this.campusCookies.length > 0
  }

  forgetSession(): void {
    this.sessionVersion++
    this.semesterGeneration++
    this.semesterFlight = null
    this.studentFlight = null
    this.campusCookies = ''
    this.studentId = ''
    this.semester = null
    this.semesterRows = []
  }

  private sessionError(): HttpError {
    return new HttpError(
      0,
      0,
      '教务数据需要先用复旦 ID 登录（服务 fdjwgl.fudan.edu.cn）。',
      ''
    )
  }

  private sessionHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': MOBILE_UA,
      'Accept': 'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
      'Cookie': this.campusCookies,
      'Referer': JwglRepository.COURSE_TABLE_URL,
    }
    return headers
  }

  private async fetchText(url: string, params?: Record<string, string>): Promise<string> {
    try {
      const response: HttpResponse = await this.httpUtil.get(url, params, this.sessionHeaders())
      return response.data
    } catch (e) {
      if (e instanceof HttpError && e.statusCode >= 500) {
        const step = url.includes('print-data') ? '课表数据' :
          url.includes('exam-arrange') ? '考试安排' : url.includes('grade') ? '成绩与 GPA' : '学期列表'
        throw new HttpError(e.statusCode, e.code,
          '教务系统读取' + step + '失败（HTTP ' + e.statusCode + '），请下拉重试。', '')
      }
      throw e as Error
    }
  }

  // ─────────────────────────── public fetches ───────────────────────────

  /**
   * Which teaching week the caller means.
   *
   * `week <= 0` resolves to the current week from the semester's start date, or
   * — when no start date is published — returns every course unfiltered rather
   * than guessing a week and silently hiding most of the timetable.
   */
  async getTimetable(week: number = 0): Promise<TimeTableEntry[]> {
    if (!this.hasSession()) {
      throw this.sessionError()
    }
    const semester: SemesterInfo = await this.currentSemester()
    const body: string = await this.fetchText(
      JwglRepository.PRINT_DATA_URL + encodeURIComponent(semester.id) + '/print-data'
    )
    const courses: Course[] = JwglRepository.parseActivities(body)
    if (courses.length === 0) {
      throw new HttpError(200, 0, '课表返回了 0 门课程，接口结构可能已变化。', body)
    }
    let targetWeek: number = week
    if (targetWeek <= 0) {
      targetWeek = 0
      if (semester.startDate.length > 0) {
        targetWeek = timeWeek(semester.startDate, new Date())
      }
    }
    const entries: TimeTableEntry[] = []
    for (const course of courses) {
      // Upstream compares the 1-based week directly against `weekIndexes`
      // (lib/model/time_table.dart:213, :234). A week of 0 means "no filter".
      if (targetWeek > 0 && course.weekIndexes.indexOf(targetWeek) < 0) {
        continue
      }
      const entry: TimeTableEntry = {
        courseName: course.name,
        teacher: course.teachers.join('、'),
        location: course.room,
        weekday: course.weekday,
        startSection: course.startUnit,
        endSection: course.endUnit,
        weeks: course.weekIndexes,
        color: JwglRepository.colorFor(course.name),
      }
      entries.push(entry)
    }
    return entries
  }

  /** Every course activity of the current semester, unexpanded. */
  async getCourses(semesterId: string = ''): Promise<Course[]> {
    if (!this.hasSession()) {
      throw this.sessionError()
    }
    const selected = semesterId ? (await this.getSemesters()).find((row: SemesterInfo) => row.id === semesterId) :
      await this.currentSemester()
    if (!selected) throw new HttpError(200, 0, AppLanguage.text($r('app.string.timetable_semester_unavailable')), '')
    const semester: SemesterInfo = selected
    const body: string = await this.fetchText(
      JwglRepository.PRINT_DATA_URL + encodeURIComponent(semester.id) + '/print-data'
    )
    return JwglRepository.parseActivities(body)
  }

  async getSemesters(forceRefresh: boolean = false): Promise<SemesterInfo[]> {
    await this.ensureSemesterBundle(forceRefresh)
    return this.semesterRows.map((row: SemesterInfo): SemesterInfo => JwglRepository.copySemester(row))
  }

  /** Server DOM default, which is independent of the newest-first display order. */
  async getCurrentSemester(forceRefresh: boolean = false): Promise<SemesterInfo> {
    await this.ensureSemesterBundle(forceRefresh)
    if (this.semester === null) throw new HttpError(200, 0, '学期列表为空，无法确定当前学期。', '')
    return JwglRepository.copySemester(this.semester)
  }

  /**
   * Exam arrangements.
   *
   * Upstream filters finished exams out with a CSS selector
   * (`tr:not(.tr-empty):not([data-finished="true"])`,
   * edu_service_repository.dart:109-111); the same two exclusions are applied
   * to the row attributes here.
   */
  async getExamSchedules(): Promise<ExamSchedule[]> {
    if (!this.hasSession()) {
      throw this.sessionError()
    }
    const studentId: string = await this.currentStudentId()
    const html: string = await this.fetchText(
      JwglRepository.EXAM_URL + encodeURIComponent(studentId)
    )
    return JwglRepository.parseExamHtml(html)
  }

  /**
   * Department GPA / rank table.
   *
   * Two chained GETs: the search-index page carries the `grade` and
   * `departmentAssoc` the search needs, and neither is guessable
   * (edu_service_repository.dart:154-210).
   */
  async getGpaList(): Promise<GpaListItem[]> {
    if (!this.hasSession()) {
      throw this.sessionError()
    }
    const studentId: string = await this.currentStudentId()
    const indexHtml: string = await this.fetchText(
      JwglRepository.GPA_INDEX_URL + encodeURIComponent(studentId)
    )
    const params: GpaSearchParams = JwglRepository.parseGpaSearchIndex(indexHtml)
    const query: Record<string, string> = {
      'studentAssoc': studentId,
      'grade': params.grade,
      'departmentAssoc': params.departmentAssoc,
      // Deliberately empty, exactly as upstream sends it (:44-49).
      'majorAssoc': '',
    }
    const body: string = await this.fetchText(JwglRepository.GPA_SEARCH_URL, query)
    return JwglRepository.parseGpaList(body)
  }

  /** Per-course grades for the current semester. */
  async getCourseGrades(semesterId: string = ''): Promise<CourseGrade[]> {
    if (!this.hasSession()) {
      throw this.sessionError()
    }
    const selectedId: string = semesterId || (await this.currentSemester()).id
    if (semesterId && !(await this.getSemesters()).some((row: SemesterInfo) => row.id === semesterId)) {
      throw new HttpError(200, 0, '学期列表中没有该学期，请刷新后重新选择。', '')
    }
    const studentId: string = await this.currentStudentId()
    const url: string = JwglRepository.GRADE_SHEET_URL + encodeURIComponent(studentId)
    const query: Record<string, string> = { 'semester': selectedId }
    const body: string = await this.fetchText(url, query)
    return JwglRepository.parseCourseGrades(body, selectedId)
  }

  // ─────────────────────────── session resolution ───────────────────────────

  /**
   * The student's internal id, memoised for the session.
   *
   * Upstream evaluates `studentTableVms[0]` before the type check, so an empty
   * list throws a bare RangeError (:81-84). Here both the missing array and the
   * missing element raise a described HttpError.
   */
  private async currentStudentId(): Promise<string> {
    if (this.studentId.length > 0) {
      return this.studentId
    }
    if (this.studentFlight !== null) return this.studentFlight
    const request: Promise<string> = this.loadStudentId(this.sessionVersion)
    this.studentFlight = request
    try { return await request }
    finally { if (this.studentFlight === request) this.studentFlight = null }
  }

  private async loadStudentId(version: number): Promise<string> {
    const semester: SemesterInfo = await this.currentSemester()
    if (version !== this.sessionVersion) throw new Error('教务会话已切换，请重新加载')
    const body: string = await this.fetchText(
      JwglRepository.PRINT_DATA_URL + encodeURIComponent(semester.id) + '/print-data'
    )
    const id: string = JwglRepository.parseStudentId(body)
    if (version !== this.sessionVersion) throw new Error('教务会话已切换，请重新加载')
    this.studentId = id
    return id
  }

  /** The default semester, memoised for the session. */
  private async currentSemester(): Promise<SemesterInfo> {
    return this.getCurrentSemester()
  }

  private async ensureSemesterBundle(forceRefresh: boolean): Promise<void> {
    if (!this.hasSession()) throw this.sessionError()
    const pending: SemesterFlight | null = this.semesterFlight
    if (pending !== null && (!forceRefresh || pending.forceRefresh)) return pending.promise
    if (!forceRefresh && this.semester !== null && this.semesterRows.length > 0) return
    this.semesterGeneration++
    const flight: SemesterFlight = {
      forceRefresh: forceRefresh,
      promise: this.loadSemesterBundle(this.sessionVersion, this.semesterGeneration)
    }
    this.semesterFlight = flight
    try { await flight.promise }
    finally { if (this.semesterFlight === flight) this.semesterFlight = null }
  }

  private async loadSemesterBundle(version: number, generation: number): Promise<void> {
    const html: string = await this.fetchText(JwglRepository.COURSE_TABLE_URL)
    const semesters: SemesterInfo[] = JwglRepository.parseSemesters(html)
    if (semesters.length === 0) {
      throw new HttpError(200, 0, '未能从选课页面解析出学期列表，接口结构可能已变化。', html)
    }
    // Upstream selects by the id the DOM's first <option> carries, not by array
    // order (time_table_repository.dart:190-194), and falls back to the newest.
    const defaultId: string = JwglRepository.parseDefaultSemesterId(html)
    const chosen: SemesterInfo | null = JwglRepository.selectDefault(semesters, defaultId)
    if (chosen === null) {
      throw new HttpError(200, 0, '学期列表为空，无法确定当前学期。', html)
    }
    if (version !== this.sessionVersion || generation !== this.semesterGeneration) {
      throw new Error('教务会话或学期列表已更新，请重新加载')
    }
    this.semesterRows = semesters
    this.semester = chosen
  }

  private static copySemester(row: SemesterInfo): SemesterInfo {
    return { id: row.id, name: row.name, startDate: row.startDate, endDate: row.endDate }
  }

  // ─────────────────────────── parsing (all pure) ───────────────────────────

  /**
   * Parse the semester list from the course-table page.
   *
   * Upstream `_parseSemesters` (time_table_repository.dart:132-170): the page
   * embeds `var semesters = JSON.parse(...)`, whose argument upstream strips of
   * all single quotes and of the `\"` escapes before decoding. The list is then
   * walked in REVERSE (:144) so the result is newest-first — that order is
   * upstream's and is preserved here. Which semester is the CURRENT one is a
   * separate question answered by `parseDefaultSemesterId` + `selectDefault`.
   *
   * The published `startDate` is a SUNDAY and upstream adds one day to make it
   * the Monday week 1 starts on (:151-154) — that adjustment is load-bearing for
   * every week calculation, so it happens here.
   */
  static parseSemesters(html: string): SemesterInfo[] {
    const match: RegExpMatchArray | null =
      html.match(/var semesters = JSON\.parse\(([\s\S]*?)\);/)
    const out: SemesterInfo[] = []
    if (!match || match.length < 2) {
      return out
    }
    const jsonText: string = match[1].replace(/'/g, '').replace(/\\"/g, '"')
    let rows: SemesterJson[] = []
    try {
      rows = JSON.parse(jsonText) as SemesterJson[]
    } catch (e) {
      throw new HttpError(200, 0, '学期列表不是合法 JSON，页面结构可能已变化。', html)
    }
    for (let i = rows.length - 1; i >= 0; i--) {
      const row: SemesterJson = rows[i]
      const id: string = JwglRepository.textOf(row.id)
      if (id.length === 0) {
        continue
      }
      const info: SemesterInfo = {
        id: id,
        name: JwglRepository.textOf(row.name),
        startDate: JwglRepository.shiftOneDay(JwglRepository.textOf(row.startDate)),
        endDate: JwglRepository.textOf(row.endDate),
      }
      out.push(info)
    }
    return out
  }

  /**
   * The semester the page marks as current, or the newest when the id is
   * missing or unknown.
   *
   * Upstream resolves the default by DOM id (:190-194) rather than by array
   * position, so an id that is not in the list must not silently select the
   * newest: that would report another term's grades as this term's. It falls
   * back only when the page names no default at all.
   */
  static selectDefault(semesters: SemesterInfo[], defaultId: string): SemesterInfo | null {
    if (semesters.length === 0) {
      return null
    }
    if (defaultId.length > 0) {
      for (const semester of semesters) {
        if (semester.id === defaultId) {
          return semester
        }
      }
      // The page named a default that is not in the list: treat the page as
      // inconsistent rather than guessing.
      return null
    }
    return semesters[0]
  }

  /** First `<option>` value under the element with id `allSemesters`. */
  static parseDefaultSemesterId(html: string): string {
    const match: RegExpMatchArray | null =
      html.match(/id="allSemesters"[\s\S]{0,4000}?<option[^>]*value="([^"]*)"/)
    return match && match.length > 1 ? match[1] : ''
  }

  /**
   * The internal student id from a print-data payload.
   *
   * Upstream reads `studentTableVms[0]["id"]` and requires an int
   * (edu_service_repository.dart:77-92).
   */
  static parseStudentId(body: string): string {
    const vms: PrintVm[] = JwglRepository.printVms(body)
    if (vms.length === 0) {
      throw new HttpError(200, 0, '课表数据缺少 studentTableVms，接口结构可能已变化。', body)
    }
    const id: string = JwglRepository.textOf(vms[0].id)
    if (id.length === 0) {
      throw new HttpError(200, 0, '课表数据缺少学生 id，接口结构可能已变化。', body)
    }
    return id
  }

  /**
   * The course activities of a print-data payload.
   *
   * Upstream `Course.fromJWGLJson` (lib/model/time_table.dart:302-320) keeps
   * `startUnit`, `endUnit`, `weekday` and `weekIndexes` 1-based and does not
   * validate them. An activity missing a course name is dropped rather than
   * rendered as a blank row.
   */
  static parseActivities(body: string): Course[] {
    const vms: PrintVm[] = JwglRepository.printVms(body)
    const out: Course[] = []
    if (vms.length === 0) {
      return out
    }
    const activities: ActivityJson[] | undefined = vms[0].activities
    if (!activities) {
      return out
    }
    for (const activity of activities) {
      const name: string = JwglRepository.textOf(activity.courseName)
      if (name.length === 0) {
        continue
      }
      const weeks: number[] = []
      const rawWeeks: Object[] | undefined = activity.weekIndexes
      if (rawWeeks) {
        for (const raw of rawWeeks) {
          const week: number = JwglRepository.intOf(raw, -1)
          if (week > 0) {
            weeks.push(week)
          }
        }
      }
      const teachers: string[] = []
      const rawTeachers: Object[] | undefined = activity.teachers
      if (rawTeachers) {
        for (const raw of rawTeachers) {
          const teacher: string = JwglRepository.textOf(raw)
          if (teacher.length > 0) {
            teachers.push(teacher)
          }
        }
      }
      const course: Course = {
        id: JwglRepository.textOf(activity.lessonId),
        code: JwglRepository.textOf(activity.lessonCode),
        name: name,
        teachers: teachers,
        room: JwglRepository.textOf(activity.room),
        weekday: JwglRepository.intOf(activity.weekday, 0),
        startUnit: JwglRepository.intOf(activity.startUnit, 0),
        endUnit: JwglRepository.intOf(activity.endUnit, 0),
        weekIndexes: weeks,
      }
      out.push(course)
    }
    return out
  }

  /**
   * The two hidden inputs from the GPA search-index page.
   *
   * Upstream requires both (`input[name="grade"]` and
   * `input[name="departmentAssoc"]`, edu_service_repository.dart:167-182) and
   * raises when either is missing, because without them the follow-up search
   * would query for the wrong cohort.
   */
  static parseGpaSearchIndex(html: string): GpaSearchParams {
    const grade: string = JwglRepository.inputValue(html, 'grade')
    const dept: string = JwglRepository.inputValue(html, 'departmentAssoc')
    if (grade.length === 0 || dept.length === 0) {
      throw new HttpError(200, 0, 'GPA 查询页缺少 grade / departmentAssoc 隐藏字段。', html)
    }
    const params: GpaSearchParams = { grade: grade, departmentAssoc: dept }
    return params
  }

  /**
   * The GPA ranking table.
   *
   * Upstream reads root `data` as an array and maps each object via
   * `GpaListItem.fromJwglJson` (edu_service_repository.dart:194-206, :647-680),
   * where every field is materialised with `.toString()`. That makes a missing
   * key the literal text "null"; here it is `''`, for the same reason as the
   * dorm parser — absent data is reported as absent.
   */
  static parseGpaList(body: string): GpaListItem[] {
    let envelope: GpaEnvelope | null = null
    try {
      envelope = JSON.parse(body) as GpaEnvelope
    } catch (e) {
      throw new HttpError(200, 0, 'GPA 查询返回的不是 JSON，可能是登录页。', body)
    }
    if (!envelope || !envelope.data) {
      throw new HttpError(200, 0, 'GPA 响应缺少 data 字段，接口结构可能已变化。', body)
    }
    const out: GpaListItem[] = []
    for (const row of envelope.data) {
      const item: GpaListItem = {
        name: JwglRepository.textOf(row.name),
        id: JwglRepository.textOf(row.code),
        gpa: JwglRepository.textOf(row.gpa),
        credits: JwglRepository.textOf(row.credit),
        rank: JwglRepository.textOf(row.ranking),
        year: JwglRepository.textOf(row.grade),
        major: JwglRepository.textOf(row.major),
        college: JwglRepository.textOf(row.department),
      }
      out.push(item)
    }
    return out
  }

  /**
   * The grade rows for one semester.
   *
   * The payload carries every semester keyed by id, and upstream indexes it
   * with the same string it sent as the query (edu_service_repository.dart:136-143).
   * A missing key is an error, not an empty list: that response means the
   * semester id was wrong, which must not render as "no grades".
   *
   * Upstream writes a literal "null" for credits (:552). Preserve real credit
   * fields when a server version supplies them; otherwise local GPA reports
   * incomplete data rather than inventing credits or converting letter grades.
   */
  static parseCourseGrades(body: string, semesterId: string): CourseGrade[] {
    let envelope: GradeEnvelope | null = null
    try {
      envelope = JSON.parse(body) as GradeEnvelope
    } catch (e) {
      throw new HttpError(200, 0, '成绩查询返回的不是 JSON，可能是登录页。', body)
    }
    if (!envelope || !envelope.semesterId2studentGrades) {
      throw new HttpError(200, 0, '成绩响应缺少 semesterId2studentGrades 字段。', body)
    }
    const rows: GradeRowJson[] | undefined =
      envelope.semesterId2studentGrades[semesterId]
    if (!rows) {
      throw new HttpError(
        200, 0,
        '成绩响应中没有该学期的数据（学期 id 可能不正确）。',
        body
      )
    }
    const out: CourseGrade[] = []
    for (const row of rows) {
      const lessonCode: string = JwglRepository.textOf(row.lessonCode)
      const courseCode: string = JwglRepository.textOf(row.courseCode)
      const name: string = JwglRepository.textOf(row.courseName)
      const nameEn: string = JwglRepository.textOf(row.courseNameEn)
      const moduleType: string = JwglRepository.textOf(row.courseModuleTypeName)
      const courseType: string = JwglRepository.textOf(row.courseType)
      const grade: CourseGrade = {
        // Upstream prefers the lesson code over the course code and the Chinese
        // name over the English one (:548-553).
        courseId: lessonCode.length > 0 ? lessonCode : courseCode,
        courseName: name.length > 0 ? name : nameEn,
        type: moduleType.length > 0 ? moduleType : courseType,
        level: JwglRepository.textOf(row.gaGrade),
        // `gp` is absent for pass/no-pass courses, where upstream leaves the
        // score null rather than inventing one (:546).
        gradePoint: JwglRepository.textOf(row.gp),
        credit: JwglRepository.textOf(row.credits ?? row.credit),
        semester: semesterId,
      }
      out.push(grade)
    }
    return out
  }

  /**
   * Exam rows from the exam-arrange HTML.
   *
   * Mirrors `Exam.fromJwglHtml` (edu_service_repository.dart:459-522), including
   * the parts that look arbitrary but are load-bearing: the third `<span>` of
   * the first cell is the room, the third `<span>` of the second cell is the
   * course category with fullwidth parentheses stripped, and the type comes
   * from the second `<div>`. Rows with fewer than four cells are dropped, and
   * rows marked finished are excluded, exactly as upstream's selector does.
   */
  static parseExamHtml(html: string): ExamSchedule[] {
    const tableMatch: RegExpMatchArray | null =
      html.match(/<table[^>]*class="[^"]*exam-table[^"]*"[^>]*>([\s\S]*?)<\/table>/)
    if (!tableMatch || tableMatch.length < 2) {
      return []
    }
    const rows: string[] = tableMatch[1].match(/<tr[^>]*>[\s\S]*?<\/tr>/g) ?? []
    const out: ExamSchedule[] = []
    for (const rowHtml of rows) {
      const openTag: string = rowHtml.substring(0, rowHtml.indexOf('>') + 1)
      if (openTag.indexOf('tr-empty') >= 0 || openTag.indexOf('data-finished="true"') >= 0) {
        continue
      }
      const cells: string[] = rowHtml.match(/<td[^>]*>[\s\S]*?<\/td>/g) ?? []
      if (cells.length < 4) {
        continue
      }
      const firstCell: string = cells[0]
      const secondCell: string = cells[1]

      let date: string = ''
      let time: string = ''
      const timeMatch: RegExpMatchArray | null =
        firstCell.match(/<div[^>]*class="[^"]*time[^"]*"[^>]*>([\s\S]*?)<\/div>/)
      if (timeMatch && timeMatch.length > 1) {
        const parts: string[] = JwglRepository.normalize(timeMatch[1]).split(' ')
        if (parts.length >= 2) {
          date = parts[0]
          time = parts[1]
        }
      }

      let location: string = ''
      const firstSpans: string[] = JwglRepository.spansOf(firstCell)
      if (firstSpans.length > 2) {
        location = firstSpans[2]
      }

      let courseName: string = ''
      let courseId: string = ''
      let category: string = ''
      const divs: string[] = secondCell.match(/<div[^>]*>[\s\S]*?<\/div>/g) ?? []
      if (divs.length > 0) {
        const firstDivSpans: string[] = JwglRepository.spansOf(divs[0])
        if (firstDivSpans.length >= 3) {
          courseName = firstDivSpans[0]
          courseId = firstDivSpans[1]
          const categoryText: string = firstDivSpans[2]
          // Upstream strips a fullwidth parenthesis pair from the category.
          if (categoryText.startsWith('（') && categoryText.endsWith('）')) {
            category = categoryText.substring(1, categoryText.length - 1).trim()
          } else {
            category = categoryText
          }
        }
      }

      let type: string = ''
      if (divs.length >= 2) {
        const typeSpans: string[] = JwglRepository.spansOf(divs[1])
        if (typeSpans.length > 0) {
          type = typeSpans[0].trim()
        }
      }

      const exam: ExamSchedule = {
        id: courseId,
        name: courseName,
        type: type,
        date: date,
        time: time,
        location: location,
        testCategory: category,
        note: JwglRepository.normalize(cells[2]),
      }
      out.push(exam)
    }
    return out
  }

  // ─────────────────────────── small helpers ───────────────────────────

  private static printVms(body: string): PrintVm[] {
    let envelope: PrintEnvelope | null = null
    try {
      envelope = JSON.parse(body) as PrintEnvelope
    } catch (e) {
      throw new HttpError(200, 0, '课表数据不是 JSON，可能是登录页。', body)
    }
    if (!envelope || !envelope.studentTableVms) {
      return []
    }
    return envelope.studentTableVms
  }

  /** Value of the `<input name="…">` whose name matches exactly. */
  private static inputValue(html: string, name: string): string {
    const tagMatch: RegExpMatchArray | null =
      html.match(new RegExp('<input[^>]*name="' + name + '"[^>]*>'))
    if (!tagMatch) {
      return ''
    }
    const valueMatch: RegExpMatchArray | null = tagMatch[0].match(/value="([^"]*)"/)
    return valueMatch && valueMatch.length > 1 ? valueMatch[1] : ''
  }

  /** Inner text of every `<span>` in a fragment, tags stripped and trimmed. */
  private static spansOf(fragment: string): string[] {
    const out: string[] = []
    const matches: string[] = fragment.match(/<span[^>]*>[\s\S]*?<\/span>/g) ?? []
    for (const raw of matches) {
      out.push(JwglRepository.normalize(raw))
    }
    return out
  }

  /**
   * Strip tags, decode the few entities this markup uses, and collapse runs of
   * whitespace — upstream's `trimAndNormalizeWhitespace()`
   * (lib/util/public_extension_methods.dart:65-68).
   */
  private static normalize(fragment: string): string {
    let text: string = fragment.replace(/<[^>]*>/g, '')
    text = text.replace(/&nbsp;/g, ' ')
    text = text.replace(/&amp;/g, '&')
    text = text.replace(/&lt;/g, '<')
    text = text.replace(/&gt;/g, '>')
    text = text.replace(/&quot;/g, '"')
    text = text.replace(/&#39;/g, "'")
    return text.replace(/\s+/g, ' ').trim()
  }

  /** Stable colour for a course name. */
  private static colorFor(name: string): string {
    let sum: number = 0
    for (let i = 0; i < name.length; i++) {
      sum = (sum + name.charCodeAt(i)) % 100000
    }
    return JwglRepository.PALETTE[sum % JwglRepository.PALETTE.length]
  }

  /** `yyyy-MM-dd` + 1 day; `''` when unparseable. */
  private static shiftOneDay(iso: string): string {
    if (iso.length === 0) {
      return ''
    }
    const dateText: string = iso.indexOf('T') >= 0 ? iso : iso + 'T00:00:00'
    const ms: number = Date.parse(dateText)
    if (isNaN(ms)) {
      return ''
    }
    const next: Date = new Date(ms + 24 * 60 * 60 * 1000)
    return formatIsoDate(next)
  }

  /** Loose JSON field → text. Objects and arrays yield `''`. */
  private static textOf(value: Object | undefined): string {
    if (value === undefined || value === null) {
      return ''
    }
    if (typeof value === 'string') {
      return value as string
    }
    if (typeof value === 'number' || typeof value === 'boolean') {
      return String(value)
    }
    return ''
  }

  /** Loose JSON field → int, with an explicit fallback. */
  private static intOf(value: Object | undefined, fallback: number): number {
    const text: string = JwglRepository.textOf(value)
    if (text.length === 0) {
      return fallback
    }
    const parsed: number = parseInt(text, 10)
    return isNaN(parsed) ? fallback : parsed
  }
}

/** `yyyy-MM-dd` in local time. */
export function formatIsoDate(date: Date): string {
  const year: string = String(date.getFullYear())
  const month: string = String(date.getMonth() + 1).padStart(2, '0')
  const day: string = String(date.getDate()).padStart(2, '0')
  return year + '-' + month + '-' + day
}

/**
 * Teaching week of `now` for a semester whose week 1 starts on `startDateIso`.
 * Returns 0 when the date is unknown or `now` is before the semester.
 */
export function timeWeek(startDateIso: string, now: Date): number {
  if (startDateIso.length === 0) {
    return 0
  }
  const ms: number = Date.parse(startDateIso + 'T00:00:00')
  if (isNaN(ms)) {
    return 0
  }
  const diff: number = now.getTime() - ms
  if (diff < 0) {
    return 0
  }
  return Math.floor(diff / (7 * 24 * 60 * 60 * 1000)) + 1
}
