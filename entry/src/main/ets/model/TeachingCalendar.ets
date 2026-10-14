import { SemesterInfo } from './Academic'

export interface CalendarTerm {
  name: string
  startDate: string
  endDate: string
  source: string
}

/** Calendar dates are local civil dates; no UTC conversion near midnight. */
export class TeachingCalendar {
  static iso(date: Date): string {
    return String(date.getFullYear()) + '-' + String(date.getMonth() + 1).padStart(2, '0') +
      '-' + String(date.getDate()).padStart(2, '0')
  }

  static validMonday(value: string): boolean {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false
    const date = new Date(value + 'T00:00:00')
    return Number.isFinite(date.getTime()) && TeachingCalendar.iso(date) === value && date.getDay() === 1
  }

  static week(start: string, now: Date = new Date()): number {
    if (!TeachingCalendar.validMonday(start)) return 0
    // UTC of civil-date components avoids a daylight-saving boundary changing a week.
    const first = new Date(start + 'T00:00:00')
    const days = (Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()) -
      Date.UTC(first.getFullYear(), first.getMonth(), first.getDate())) / 86400000
    return Math.floor(days / 7) + 1
  }

  static current(terms: CalendarTerm[], now: Date = new Date()): CalendarTerm | undefined {
    const today = TeachingCalendar.iso(now)
    const sorted = terms.filter((term: CalendarTerm) => TeachingCalendar.validMonday(term.startDate))
      .sort((a: CalendarTerm, b: CalendarTerm) => a.startDate.localeCompare(b.startDate))
    const active = sorted.filter((term: CalendarTerm) => term.startDate <= today &&
      (!term.endDate || term.endDate >= today))
    if (active.length > 0) return active[active.length - 1]
    // During vacations keep the upcoming semester, with a pre-term week indication.
    return sorted.find((term: CalendarTerm) => term.startDate > today) ?? sorted[sorted.length - 1]
  }

  static termAtDate(terms: CalendarTerm[], now: Date = new Date()): CalendarTerm | undefined {
    const today: string = TeachingCalendar.iso(now)
    // Holidays between teaching periods still belong to the preceding term.
    // Never overwrite a past selection with a future term before it begins.
    return terms.filter((term: CalendarTerm) => TeachingCalendar.validMonday(term.startDate) && term.startDate <= today)
      .sort((a: CalendarTerm, b: CalendarTerm) => b.startDate.localeCompare(a.startDate))[0]
  }

  static semester(semesters: SemesterInfo[], now: Date = new Date()): SemesterInfo | undefined {
    const today = TeachingCalendar.iso(now)
    const rows = semesters.filter((row: SemesterInfo) => TeachingCalendar.validMonday(row.startDate))
      .sort((a: SemesterInfo, b: SemesterInfo) => b.startDate.localeCompare(a.startDate))
    return rows.find((row: SemesterInfo) => row.startDate <= today) ?? rows[rows.length - 1]
  }

  /** Resolve a chosen Monday to a real catalog entry, never synthesize an ID
   * or silently relabel the current server timetable as a historical one. */
  static forMonday(semesters: SemesterInfo[], monday: string): SemesterInfo | undefined {
    if (!TeachingCalendar.validMonday(monday)) return undefined
    const rows = semesters.filter((row: SemesterInfo) => TeachingCalendar.validMonday(row.startDate))
      .sort((a: SemesterInfo, b: SemesterInfo) => a.startDate.localeCompare(b.startDate))
    const exact = rows.find((row: SemesterInfo) => row.startDate === monday)
    if (exact !== undefined) return exact
    for (let index: number = rows.length - 1; index >= 0; index--) {
      const row: SemesterInfo = rows[index]
      const days: number = (Date.parse(monday + 'T00:00:00') - Date.parse(row.startDate + 'T00:00:00')) / 86400000
      if (days < 0 || days > 180) continue
      if (row.endDate && monday > row.endDate) continue
      if (index + 1 < rows.length && monday >= rows[index + 1].startDate) continue
      return row
    }
    return undefined
  }

  /** Only explicit official date ranges are accepted. OCR ambiguity is an error,
   * never a guessed September/February Monday. Both image and text calendars use this.
   */
  static parse(text: string, source: string): CalendarTerm[] {
    const compact = text.replace(/\s/g, '').replace(/[－—～]/g, '-')
    const year = compact.match(/(20\d{2})-?(20\d{2})学年/)
    if (!year || Number(year[2]) !== Number(year[1]) + 1) return []
    const terms: CalendarTerm[] = []
    for (let index = 1; index <= 2; index++) {
      const label = index === 1 ? '(?:第一学期|秋季学期)' : '(?:第二学期|春季学期)'
      const pattern = new RegExp(label + '[^。；]{0,120}?(20\\d{2})年(\\d{1,2})月(\\d{1,2})日(?:至|-|到)(?:(20\\d{2})年)?(\\d{1,2})月(\\d{1,2})日')
      const match = compact.match(pattern)
      if (!match) continue
      const published = match[1] + '-' + match[2].padStart(2, '0') + '-' + match[3].padStart(2, '0')
      let start = published
      // Published university ranges can begin at orientation week 0 (Sunday).
      // In that case require an explicit "M月D日上课" date in the same term;
      // never blindly add a day, or infer a September Monday.
      if (!TeachingCalendar.validMonday(start)) {
        const lessons = compact.match(/\d{1,2}月\d{1,2}日上课/g) ?? []
        const candidates: string[] = []
        for (const lesson of lessons) {
          const parts = lesson.match(/(\d{1,2})月(\d{1,2})日上课/)
          if (!parts) continue
          const candidateYear = Number(match[1]) + (Number(parts[1]) < Number(match[2]) ? 1 : 0)
          const candidate = String(candidateYear) + '-' + parts[1].padStart(2, '0') + '-' + parts[2].padStart(2, '0')
          const delay = (new Date(candidate + 'T00:00:00').getTime() - new Date(published + 'T00:00:00').getTime()) / 86400000
          if (TeachingCalendar.validMonday(candidate) && delay >= 0 && delay <= 14 && !candidates.includes(candidate)) candidates.push(candidate)
        }
        // Two different first-week Mondays would be ambiguous (e.g. colleges).
        if (candidates.length !== 1) continue
        start = candidates[0]
      }
      const endYear = match[4] || String(Number(match[1]) + (Number(match[5]) < Number(match[2]) ? 1 : 0))
      const end = endYear + '-' + match[5].padStart(2, '0') + '-' + match[6].padStart(2, '0')
      const span = (new Date(end + 'T00:00:00').getTime() - new Date(start + 'T00:00:00').getTime()) / 86400000
      if (TeachingCalendar.validMonday(start) && TeachingCalendar.iso(new Date(end + 'T00:00:00')) === end && span >= 70 && span <= 180 &&
        Number(match[1]) >= Number(year[1]) && Number(endYear) <= Number(year[2])) {
        terms.push({ name: year[1] + '-' + year[2] + ' / ' + String(index), startDate: start,
          endDate: end, source: source })
      }
    }
    return terms
  }
}
