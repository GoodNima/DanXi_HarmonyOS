import { CourseGrade, ExamSchedule, GpaListItem, SemesterInfo } from '../model/Academic'
import { AcademicPresentation } from './AcademicPresentation'
import { AppLanguage } from './AppLanguage'
import { FduAuthCancelledError } from './FduWebAuth'

export interface AcademicSource {
  getSemesters(): Promise<SemesterInfo[]>
  getCurrentSemester(): Promise<SemesterInfo>
  getExamSchedules(): Promise<ExamSchedule[]>
  getCourseGrades(semesterId: string): Promise<CourseGrade[]>
  getGpaList(): Promise<GpaListItem[]>
  getCourseGradesFromDataCenter(): Promise<CourseGrade[]>
}

export class AcademicResult {
  semesters: SemesterInfo[] = []
  semesterId: string = ''
  exams: ExamSchedule[] = []
  grades: CourseGrade[] = []
  ranks: GpaListItem[] = []
  examError: string = ''
  gradeError: string = ''
  rankError: string = ''
  semesterError: string = ''
  fallback: boolean = false
}

/** A stale semester/account request never replaces a newer selection. */
export class AcademicRequest {
  private version: number = 0
  invalidate(): void { this.version++ }

  async load(source: AcademicSource, graduate: boolean, semesterId: string): Promise<AcademicResult | undefined> {
    const version = ++this.version
    const result = new AcademicResult()
    if (graduate) {
      try { result.grades = await source.getCourseGrades('') }
      catch (e) { result.gradeError = AcademicRequest.errorText(e) }
    } else {
      try {
        result.semesters = await source.getSemesters()
        if (version !== this.version) return undefined
        const current = semesterId.length > 0 ? result.semesters.find((row: SemesterInfo) => row.id === semesterId) :
          await source.getCurrentSemester()
        if (version !== this.version) return undefined
        if (current === undefined) throw new Error(AppLanguage.text($r('app.string.academic_semester_missing')))
        result.semesterId = current.id
        // Errors stay per service: missing grades must not erase valid exams/GPA.
        await Promise.all([
          source.getExamSchedules().then((rows: ExamSchedule[]) => {
            result.exams = AcademicPresentation.semesterExams(rows, current, result.semesters)
          }).catch((e: Object) => { result.examError = AcademicRequest.errorText(e) }),
          source.getCourseGrades(current.id).then((rows: CourseGrade[]) => { result.grades = rows })
            .catch((e: Object) => { result.gradeError = AcademicRequest.errorText(e) }),
          source.getGpaList().then((rows: GpaListItem[]) => { result.ranks = rows })
            .catch((e: Object) => { result.rankError = AcademicRequest.errorText(e) })
        ])
      } catch (e) {
        result.semesterError = AcademicRequest.errorText(e)
        if (version !== this.version) return undefined
        if (!(e instanceof FduAuthCancelledError)) {
          try { result.grades = await source.getCourseGradesFromDataCenter(); result.fallback = true }
          catch (fallbackError) { result.gradeError = AcademicRequest.errorText(fallbackError) }
        }
      }
    }
    return version === this.version ? result : undefined
  }

  private static errorText(error: Object): string {
    return String(error).replace(/^[A-Za-z]+Error: /, '').replace(/^Error: /, '')
  }
}
