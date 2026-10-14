import { Person } from '../model/Person'
import { AcademicCalendar } from './AcademicCalendar'

export class AcademicAccount {
  static group(): string {
    return Person.fromJson(AppStorage.get<string>('app_person') ?? '').academicGroup
  }
  static isGraduate(): boolean { return AcademicAccount.group() === 'postgraduate' }
  static requireSelection(): void {
    if (AcademicAccount.group() === 'unknown') throw new Error('请先在“我的 → 教务账号类型”选择本科生或研究生。')
  }
  static async semesterStart(): Promise<string> {
    return AcademicCalendar.start()
  }
}
