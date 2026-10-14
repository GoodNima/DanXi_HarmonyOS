import { CourseGrade, ExamSchedule, GpaListItem, SemesterInfo } from '../model/Academic'

export interface AcademicRankRow {
  item: GpaListItem
  percentile: string
  isMe: boolean
}

/** Presentation follows the original exam hybrid view and department rank table. */
export class AcademicPresentation {
  /** Use the school's published cumulative result, including its credit scope.
   * Semester grade lists can omit credits and retake rules, so never rebuild
   * a plausible-looking cumulative GPA from an incomplete set of courses. */
  static officialGpa(rows: GpaListItem[], studentId: string): GpaListItem | undefined {
    const me: GpaListItem | undefined = AcademicPresentation.userGpa(rows, studentId)
    if (me === undefined || !/^\d+(\.\d+)?$/.test(me.gpa.trim()) || Number(me.gpa) > 4 ||
      !/^\d+(\.\d+)?$/.test(me.credits.trim())) return undefined
    return me
  }
  static userGpa(rows: GpaListItem[], studentId: string): GpaListItem | undefined {
    return studentId.length > 0 ? rows.find((row: GpaListItem) => row.id === studentId) : undefined
  }

  static ranks(rows: GpaListItem[], studentId: string, sameMajor: boolean): AcademicRankRow[] {
    const me = AcademicPresentation.userGpa(rows, studentId)
    const selected = rows.filter((row: GpaListItem) => !sameMajor || me === undefined || row.major === me.major)
      .slice().sort((a: GpaListItem, b: GpaListItem) => AcademicPresentation.rank(a.rank) - AcademicPresentation.rank(b.rank))
    let lastRank = '', ordinal = 1
    return selected.map((row: GpaListItem, index: number): AcademicRankRow => {
      if (index === 0 || row.rank !== lastRank) ordinal = index + 1
      lastRank = row.rank
      return { item: row, percentile: (100 * ordinal / selected.length).toFixed(2) + '%',
        isMe: me !== undefined && row === me }
    })
  }

  private static rank(value: string): number {
    return /^\d+$/.test(value.trim()) ? Number(value.trim()) : Number.MAX_SAFE_INTEGER
  }

  static examGrade(exam: ExamSchedule, grades: CourseGrade[]): CourseGrade | undefined {
    if (exam.type.includes('补') || exam.type.includes('缓') || exam.id.length === 0) return undefined
    return grades.find((grade: CourseGrade) => grade.courseId === exam.id)
  }

  static otherExam(exam: ExamSchedule): boolean {
    return exam.testCategory.trim() === '论文' || exam.testCategory.trim() === '其他' ||
      (exam.type !== '期末考试' && exam.type !== '期末')
  }

  static unmatchedGrades(exams: ExamSchedule[], grades: CourseGrade[]): CourseGrade[] {
    return grades.filter((grade: CourseGrade) => grade.courseId.length === 0 ||
      !exams.some((exam: ExamSchedule) => exam.id.length > 0 && exam.id === grade.courseId))
  }

  /** Date boundaries come from the academic server, never inferred from today's date. */
  static semesterExams(exams: ExamSchedule[], semester: SemesterInfo, semesters: SemesterInfo[]): ExamSchedule[] {
    const start = semester.startDate
    const next = semesters.filter((row: SemesterInfo) => row.startDate > start)
      .sort((a: SemesterInfo, b: SemesterInfo) => a.startDate.localeCompare(b.startDate))[0]
    const end = semester.endDate ?? ''
    if (!/^\d{4}-\d{2}-\d{2}$/.test(start)) return exams.slice()
    return exams.filter((exam: ExamSchedule) => {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(exam.date)) return true
      return exam.date >= start && (end.length > 0 ? exam.date <= end : next === undefined || exam.date < next.startDate)
    })
  }

  static examsCalendar(exams: ExamSchedule[], now: Date = new Date()): string {
    const stamp = now.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z')
    const lines: string[] = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//DanXi//Exams//ZH', 'CALSCALE:GREGORIAN']
    let count = 0
    for (const exam of exams) {
      const range = /^(\d{1,2}:\d{2})\s*[~～—–-]\s*(\d{1,2}:\d{2})$/.exec(exam.time.trim())
      if (range === null) continue
      const begin = AcademicPresentation.examTime(exam.date, range[1])
      const end = AcademicPresentation.examTime(exam.date, range[2])
      if (begin === undefined || end === undefined || end.getTime() <= begin.getTime()) continue
      count++
      lines.push('BEGIN:VEVENT', 'UID:danxi-exam-' + encodeURIComponent(exam.id + ':' + exam.date + ':' + exam.time) + '@local',
        'DTSTAMP:' + stamp, 'DTSTART:' + begin.toISOString().replace(/[-:]/g, '').replace('.000Z', 'Z'),
        'DTEND:' + end.toISOString().replace(/[-:]/g, '').replace('.000Z', 'Z'),
        'SUMMARY:' + AcademicPresentation.escape(exam.name), 'LOCATION:' + AcademicPresentation.escape(exam.location),
        'DESCRIPTION:' + AcademicPresentation.escape(exam.testCategory + ' ' + exam.type + '\n' + exam.note), 'END:VEVENT')
    }
    if (count === 0) throw new Error('No exams with valid published dates and times')
    lines.push('END:VCALENDAR')
    return lines.map((line: string) => AcademicPresentation.fold(line)).join('\r\n') + '\r\n'
  }

  private static examTime(day: string, time: string): Date | undefined {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return undefined
    const date = day.split('-'), clock = time.split(':')
    const year = Number(date[0]), month = Number(date[1]), dateOfMonth = Number(date[2])
    const hour = Number(clock[0]), minute = Number(clock[1])
    if (hour > 23 || minute > 59) return undefined
    const check = new Date(Date.UTC(year, month - 1, dateOfMonth))
    if (check.getUTCFullYear() !== year || check.getUTCMonth() !== month - 1 || check.getUTCDate() !== dateOfMonth) return undefined
    return new Date(Date.UTC(year, month - 1, dateOfMonth, hour - 8, minute))
  }

  private static escape(value: string): string {
    return value.replace(/\\/g, '\\\\').replace(/\r?\n/g, '\\n').replace(/;/g, '\\;').replace(/,/g, '\\,')
  }

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
}
