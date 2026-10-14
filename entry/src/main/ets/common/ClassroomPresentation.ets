import { EmptyClassroom, TimetableHelper } from '../model/Academic'
import { Constant } from './Constant'

export interface ClassroomPeriodGroup {
  name: Resource
  periods: number[]
}

/** Original campus/building and 5/5/3 slot structure; filters never alter server data. */
export class ClassroomPresentation {
  static readonly CAMPUSES: string[] = Constant.CAMPUS_NAMES
  static readonly GROUPS: ClassroomPeriodGroup[] = [
    { name: $r('app.string.classroom_morning'), periods: [1, 2, 3, 4, 5] },
    { name: $r('app.string.classroom_afternoon'), periods: [6, 7, 8, 9, 10] },
    { name: $r('app.string.classroom_evening'), periods: [11, 12, 13] }
  ]

  static buildings(campus: string): string[] {
    if (campus === '枫林') return ['F']
    if (campus === '江湾') return ['J']
    if (campus === '张江') return ['Z']
    return ['HGD', 'HGX', 'H2', 'H3', 'H4', 'H5', 'H6', 'HQ']
  }

  static campus(building: string): string {
    if (building.startsWith('F')) return '枫林'
    if (building.startsWith('J')) return '江湾'
    if (building.startsWith('Z')) return '张江'
    return '邯郸'
  }

  static slotFree(item: EmptyClassroom, slot: number): boolean | undefined {
    if (!Number.isInteger(slot) || slot < 1 || slot > 13 || item.freePeriods === undefined) return undefined
    return item.freePeriods.includes(slot)
  }

  /** A selected range requires every slot to be confirmed free. An unknown row cannot pass this filter. */
  static matches(item: EmptyClassroom, start: number = 0, end: number = 0): boolean {
    if (item.freePeriods === undefined) return false
    if (start === 0 && end === 0) return item.freePeriods.some((slot: number) => slot >= 1 && slot <= 13)
    if (!Number.isInteger(start) || !Number.isInteger(end) || start < 1 || end > 13 || start > end) return false
    for (let slot = start; slot <= end; slot++) {
      if (ClassroomPresentation.slotFree(item, slot) !== true) return false
    }
    return true
  }

  static visible(rows: EmptyClassroom[], onlyFree: boolean, start: number = 0, end: number = 0): EmptyClassroom[] {
    return rows.filter((row: EmptyClassroom) => !onlyFree || ClassroomPresentation.matches(row, start, end))
  }

  /** Compact consecutive ranges retain gaps instead of implying uninterrupted availability. */
  static freeRanges(periods: number[]): string {
    const sorted: number[] = periods.filter((slot: number) => Number.isInteger(slot) && slot >= 1 && slot <= 13)
      .filter((slot: number, index: number, all: number[]) => all.indexOf(slot) === index).sort((a: number, b: number) => a - b)
    const ranges: string[] = []
    let begin = 0, last = 0
    for (const slot of sorted) {
      if (begin === 0) { begin = slot; last = slot }
      else if (slot === last + 1) last = slot
      else { ranges.push(begin === last ? String(begin) : String(begin) + '–' + String(last)); begin = slot; last = slot }
    }
    if (begin > 0) ranges.push(begin === last ? String(begin) : String(begin) + '–' + String(last))
    return ranges.join('、')
  }

  static buildingName(building: string): string {
    const names: Record<string, string> = {}
    names['H2'] = '第二教学楼'; names['H3'] = '第三教学楼'; names['H4'] = '第四教学楼'
    names['H5'] = '第五教学楼'; names['H6'] = '第六教学楼'; names['HGX'] = '光华楼西辅楼'; names['HGD'] = '光华楼东辅楼'
    names['HQ'] = '新闻学院'; names['J'] = '江湾校区'; names['Z'] = '张江校区'; names['F'] = '枫林校区'
    return names[building] ?? building
  }
  static previewLabel(building: string, day: string): string {
    return ClassroomPresentation.buildingName(building) + ' · ' + day
  }

  static day(date: Date): string {
    return String(date.getFullYear()) + '-' + String(date.getMonth() + 1).padStart(2, '0') + '-' +
      String(date.getDate()).padStart(2, '0')
  }

  static dateOffset(now: Date, offset: number): Date {
    const date = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 12)
    date.setDate(date.getDate() + offset)
    return date
  }

  static validDay(day: string, now: Date = new Date()): boolean {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return false
    const date = new Date(day + 'T12:00:00')
    return Number.isFinite(date.getTime()) && ClassroomPresentation.day(date) === day &&
      day >= ClassroomPresentation.day(ClassroomPresentation.dateOffset(now, -1)) &&
      day <= ClassroomPresentation.day(ClassroomPresentation.dateOffset(now, 14))
  }

  /** The original highlights the latest starting slot, only on the queried current date. */
  static currentSlot(day: string, now: Date = new Date()): number {
    if (day !== ClassroomPresentation.day(now)) return 0
    const clock = now.getHours() * 60 + now.getMinutes()
    let current = 0
    for (let slot = 1; slot <= TimetableHelper.SLOT_START_TIMES.length; slot++) {
      const time = TimetableHelper.getSlotStartTime(slot).split(':')
      if (clock >= Number(time[0]) * 60 + Number(time[1])) current = slot
    }
    return current <= 13 ? current : 0
  }
}
