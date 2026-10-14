import { AppLanguage } from '../common/AppLanguage'
import { CampusPreviewItem } from './CampusPreviewItem'

/** Contracts copied from pinned DanXi Fudan sports / data-centre / QR sources. */
export class CampusUtilitySummary {
  items: CampusPreviewItem[] = []
  feature: string = ''
  value: string = ''
  description: string = ''
  secondary: string = ''
  updatedAt: number = 0
  status: string = 'ready'
  tone: string = ''
}

export class CampusUtilityParams { feature: string = 'sports' }

export class CampusAccessCard {
  id: string = ''
  name: string = ''
  status: string = ''
  permission: string = ''
  expireDate: string = ''
  balance: string = ''
}

export class ExerciseItem { title: string = ''; times: number | undefined = undefined }
export class ExerciseRecord { title: string = ''; result: string = ''; score: string = ''; comment: string = '' }
export class SportsSnapshot {
  items: ExerciseItem[] = []
  records: ExerciseRecord[] = []
  updatedAt: number = 0
  /** No missing/invalid count is silently turned into zero. */
  category(index: number): number | undefined {
    const names: string[][] = [['早操', '加章1'],
      ['夜跑', '仰卧起坐', '引体向上', '中长跑', '立定跳远', '加章2'],
      ['课外活动', '晚锻炼', '周末上午', '加章3']]
    let value: number = 0
    let found: boolean = false
    for (const item of this.items) {
      if (names[index]?.includes(item.title) && item.times !== undefined) {
        value += item.times; found = true
      }
    }
    return found ? value : undefined
  }
}

export class LifeCode { value: string = ''; updatedAt: number = 0 }
export class LifeCodeTermsError extends Error {
  constructor() { super(AppLanguage.text($r('app.string.utility_code_terms_required'))); this.name = 'LifeCodeTermsError' }
}
