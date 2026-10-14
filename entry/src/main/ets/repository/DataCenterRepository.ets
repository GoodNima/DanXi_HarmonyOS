import { BaseRepository } from './BaseRepository'
import { CourseGrade } from '../model/Academic'
import { HttpError } from '../util/HttpUtil'

interface DataCenterGrades { data?: Object[][]; recordsFiltered?: number; recordsTotal?: number }

/** Pinned upstream data_center_repository.dart, authenticated by the shared my.fudan session. */
export class DataCenterRepository extends BaseRepository {
  static readonly GRADES_URL: string = 'https://my.fudan.edu.cn/data_tables/bks_xx_cj.json'
  private static readonly PAGE_SIZE: number = 100
  private static readonly PAGE_LIMIT: number = 20

  async getCourseGrades(cookies: string): Promise<CourseGrade[]> {
    const result: CourseGrade[] = []
    const seen: Set<string> = new Set<string>()
    for (let page: number = 0; page < DataCenterRepository.PAGE_LIMIT; page++) {
      const offset: number = page * DataCenterRepository.PAGE_SIZE
      const form: Record<string, string> = { 'start': String(offset), 'length': String(DataCenterRepository.PAGE_SIZE) }
      const headers: Record<string, string> = { 'Cookie': cookies, 'Referer': 'https://my.fudan.edu.cn/' }
      const response = await this.httpUtil.postForm(DataCenterRepository.GRADES_URL,
        form, headers)
      const envelope: DataCenterGrades = DataCenterRepository.envelope(response.data)
      const rows: CourseGrade[] = DataCenterRepository.parseCourseGrades(response.data)
      let added: number = 0
      for (const row of rows) {
        const key: string = row.courseId + '\n' + row.courseName + '\n' + row.semester + '\n' + row.level
        if (seen.has(key)) continue
        seen.add(key)
        result.push(row)
        added++
      }
      const total: number | undefined = envelope.recordsFiltered ?? envelope.recordsTotal
      if (rows.length > 0 && added === 0) throw new HttpError(200, 0, '数据中心返回了重复成绩页，请稍后重试。', '')
      if (rows.length < DataCenterRepository.PAGE_SIZE ||
        (total !== undefined && Number.isFinite(total) && offset + rows.length >= total)) return result
    }
    throw new HttpError(200, 0, '数据中心成绩页数超过读取上限，请稍后重试。', '')
  }

  static parseCourseGrades(body: string): CourseGrade[] {
    const envelope: DataCenterGrades = DataCenterRepository.envelope(body)
    const out: CourseGrade[] = []
    for (const row of envelope.data ?? []) {
      if (!Array.isArray(row) || row.length < 7) throw new HttpError(200, 0, '数据中心成绩字段不完整。', '')
      const semester: string = DataCenterRepository.text(row[2]) || DataCenterRepository.text(row[1])
      const grade: CourseGrade = {
        courseId: DataCenterRepository.text(row[0]), courseName: DataCenterRepository.text(row[3]),
        type: semester, credit: DataCenterRepository.text(row[4]), level: DataCenterRepository.text(row[5]),
        gradePoint: DataCenterRepository.text(row[6]), semester: semester
      }
      if (!grade.courseId || !grade.courseName) throw new HttpError(200, 0, '数据中心成绩缺少课程信息。', '')
      out.push(grade)
    }
    return out
  }

  private static envelope(body: string): DataCenterGrades {
    let parsed: DataCenterGrades | null = null
    try { parsed = JSON.parse(body) as DataCenterGrades }
    catch (e) { throw new HttpError(200, 0, '数据中心成绩响应不是 JSON，请重新加载。', '') }
    if (parsed === null || !Array.isArray(parsed.data)) {
      throw new HttpError(200, 0, '数据中心成绩响应缺少 data 字段。', '')
    }
    return parsed
  }

  private static text(value: Object | undefined | null): string {
    if (value === undefined || value === null) return ''
    if (typeof value === 'string' || typeof value === 'number') return String(value).trim()
    return ''
  }
}
