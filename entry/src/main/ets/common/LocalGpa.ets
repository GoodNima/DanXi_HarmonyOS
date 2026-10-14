import { CourseGrade } from '../model/Academic'

export class LocalGpaResult {
  gpa: string = ''
  credits: string = ''
  included: number = 0
  excluded: number = 0
  incomplete: number = 0
}

/** GPA = sum(published course GP * credits) / sum(included credits).
 * Use the school's per-course GP: undergraduate letter grades can represent
 * a range, so converting letters to a fixed number would be inaccurate.
 * Scope is the supplied grade list, not a claim of cumulative/degree GPA.
 */
export class LocalGpa {
  static calculate(grades: CourseGrade[], graduate: boolean = false): LocalGpaResult {
    const result = new LocalGpaResult()
    const seen: Set<string> = new Set<string>()
    let credits: number = 0
    let weighted: number = 0
    for (const grade of grades) {
      const key: string = JSON.stringify([grade.courseId, grade.courseName, grade.semester,
        grade.level, grade.gradePoint, grade.credit ?? ''])
      // Remove identical transport duplicates, retaining distinct attempts.
      if (seen.has(key)) continue
      seen.add(key)
      const level: string = grade.level.trim().toUpperCase()
      const graduateExcluded: boolean = graduate && /补修|必修环节|考查/.test(grade.type)
      if (['P', 'NP', '通过', '不通过', '合格', '不合格'].includes(level) ||
        (!graduate && level.startsWith('*')) || graduateExcluded) {
        result.excluded++; continue
      }
      const pointText: string = grade.gradePoint.trim()
      const creditText: string = (grade.credit ?? '').trim()
      if (!/^\d+(\.\d+)?$/.test(pointText) || !/^\d+(\.\d+)?$/.test(creditText) ||
        Number(pointText) > 4 || Number(creditText) <= 0) { result.incomplete++; continue }
      const point: number = Number(pointText)
      const credit: number = Number(creditText)
      if (!Number.isFinite(point) || !Number.isFinite(credit)) { result.incomplete++; continue }
      credits += credit; weighted += point * credit; result.included++
    }
    if (credits > 0 && Number.isFinite(weighted) && Number.isFinite(credits)) {
      result.gpa = (weighted / credits).toFixed(2)
      result.credits = String(Number(credits.toFixed(4)))
    }
    return result
  }
}
