/** Port of upstream graduate_exam_repository.dart and Course.fromPGPart.
 * Graduate scores and course selection use different services from fdjwgl.
 */
import { HttpUtil } from '../util/HttpUtil'
import { Course, CourseGrade, TimeTableEntry, TimetableHelper } from '../model/Academic'
import { parseObject, jsonObject, jsonArray, jsonString } from '../model/Forum'
import { AcademicAccount } from '../common/AcademicAccount'
import { GraduateHistory } from '../model/GraduateHistory'

function display(row: Record<string, Object>, key: string): string {
  const value = row[key]
  return typeof value === 'string' || typeof value === 'number' ? String(value) : ''
}

export class GraduateRepository {
  static readonly SCORE_ENTRY: string = 'https://yzsfwapp.fudan.edu.cn/gsapp/sys/wdcjapp/*default/index.do'
  static readonly SCORE_API: string = 'https://yzsfwapp.fudan.edu.cn/gsapp/sys/wdcjapp/modules/xscjcx/jdjscjcx.do'
  // University FAQ publishes HTTP course-selection hosts. Passwords are only filled on HTTPS id.fudan.edu.cn.
  static readonly TIMETABLE_HOSTS: string[] = [
    'http://yjsxk.fudan.edu.cn', 'http://yjsxktest.fudan.sh.cn'
  ]
  static readonly TIMETABLE_PATH: string = '/yjsxkapp/sys/xsxkappfudan/xsxkCourse/loadKbxx.do'
  static readonly HISTORY_ENTRY: string = 'https://yzsfwapp.fudan.edu.cn/gsapp/sys/wdrcappfudan/*default/index.do?type=add#/wdrc'
  static readonly HISTORY_API: string = 'https://yzsfwapp.fudan.edu.cn/gsapp/sys/wdrcappfudan/wdrc/loadRcxx.do'

  static async history(monday: string, cookies: string): Promise<Course[]> {
    const response = await HttpUtil.getInstance().postForm(GraduateRepository.HISTORY_API, GraduateHistory.range(monday),
      { 'Cookie': cookies, 'Referer': GraduateRepository.HISTORY_ENTRY, 'Accept': 'application/json', 'Authorization': '',
        'User-Agent': HttpUtil.BROWSER_UA })
    return GraduateHistory.parse(response.data, monday)
  }

  static parseScores(body: string): CourseGrade[] {
    const data = parseObject(body)
    const scores = jsonObject(jsonObject(data, 'datas') ?? {}, 'jdjscjcx')
    if (String(data['code']) !== '0' || scores === null || !Array.isArray(scores['rows'])) {
      throw new Error('研究生成绩数据未返回，请重新加载')
    }
    return jsonArray(scores, 'rows').map((raw: Object): CourseGrade => {
      const row = raw as Record<string, Object>
      return { courseId: display(row, 'KCDM'), courseName: display(row, 'KCMC'), type: display(row, 'KCLBMC'),
        level: display(row, 'CJ'), gradePoint: display(row, 'JDZ'), credit: display(row, 'XF'), semester: '' }
    })
  }

  static parseCourses(body: string): Course[] {
    const data = parseObject(body)
    if (!Array.isArray(data['results'])) throw new Error('研究生课表未返回课程数据，请重试或切换选课入口')
    const rows = jsonArray(data, 'results')
    // The iOS contract explicitly excludes non-current rows without ZCBH.
    return rows.filter((raw: Object) => display(raw as Record<string, Object>, 'ZCBH').length > 0)
      .map((raw: Object, index: number): Course => {
      const row = raw as Record<string, Object>
      const weeks: number[] = []
      const mask = display(row, 'ZCBH')
      for (let bit = 0; bit < mask.length; bit++) if (mask.charAt(bit) === '1') weeks.push(bit + 1)
      const day = Number(row['XQ'])
      const unit = Number(row['KSJCDM'])
      if (!display(row, 'KCMC') || day < 1 || day > 7 || !Number.isInteger(day) ||
        !Number.isInteger(unit) || unit < 1 || !/^[01]+$/.test(mask)) throw new Error('研究生课表字段不完整，请重试')
      const classCode: string = display(row, 'BJDM').trim()
      return { id: String(index), code: display(row, 'KCDM') || (classCode.length > 10 ? classCode.slice(10) : ''), name: display(row, 'KCMC'),
        teachers: display(row, 'JSXM') ? [display(row, 'JSXM')] : [], room: display(row, 'JASMC'),
        weekday: day, startUnit: unit, endUnit: unit, weekIndexes: weeks }
    })
  }

  static async scores(cookies: string): Promise<CourseGrade[]> {
    const response = await HttpUtil.getInstance().get(GraduateRepository.SCORE_API, undefined,
      { 'Cookie': cookies, 'Referer': GraduateRepository.SCORE_ENTRY })
    return GraduateRepository.parseScores(response.data)
  }

  static async courses(host: string, cookies: string): Promise<Course[]> {
    const response = await HttpUtil.getInstance().get(host + GraduateRepository.TIMETABLE_PATH + '?_=' + Date.now(),
      undefined, { 'Cookie': cookies, 'Referer': host + '/wsxk' })
    return GraduateRepository.parseCourses(response.data)
  }

  static async entries(courses: Course[], week: number): Promise<TimeTableEntry[]> {
    const targetWeek = week > 0 ? week : TimetableHelper.weekOf(await AcademicAccount.semesterStart(), new Date())
    return courses.filter((course: Course) => targetWeek <= 0 || course.weekIndexes.includes(targetWeek))
      .map((course: Course): TimeTableEntry => ({
        courseName: course.name, teacher: course.teachers.join('、'), location: course.room,
        weekday: course.weekday, startSection: course.startUnit, endSection: course.endUnit,
        weeks: course.weekIndexes, color: '#4A90D9'
      }))
  }
}
