import { i18n } from '@kit.LocalizationKit'
import { AppLanguage } from './AppLanguage'
import { AnnouncementConfig } from './AnnouncementConfig'

export interface CampusLunarDate { month: number; day: number; leap: boolean; eve: boolean }

/** The system calendar owns lunar conversion, including leap months and the
 * variable last day of the year. A date must never be guessed from a table. */
export class CampusGreeting {
  /** Keep the upstream name-bearing welcome as the main line. Unknown names
   * stay a real account ID or a natural visitor greeting, never an invented name. */
  static welcome(name: string, loggedIn: boolean, revision: number): string {
    const display: string = name.trim()
    return loggedIn && display ? AppLanguage.text($r('app.string.campus_welcome_name'), revision).replace('{name}', display) :
      AppLanguage.text($r('app.string.campus_welcome_guest'), revision)
  }

  static lunar(now: Date): CampusLunarDate {
    const result: CampusLunarDate = { month: 0, day: 0, leap: false, eve: false }
    try {
      const calendar: i18n.Calendar = i18n.getCalendar('zh-Hans', 'chinese')
      calendar.setTime(now)
      result.month = calendar.get('month') + 1
      result.day = calendar.get('date')
      result.leap = calendar.get('is_leap_month') !== 0
      const tomorrow: Date = new Date(now.getTime())
      tomorrow.setDate(tomorrow.getDate() + 1)
      calendar.setTime(tomorrow)
      result.eve = calendar.get('month') === 0 && calendar.get('date') === 1 && calendar.get('is_leap_month') === 0
    } catch (e) { /* An unavailable calendar falls back to time-based greetings. */ }
    return result
  }

  static matches(date: string, now: Date, lunar: CampusLunarDate): boolean {
    const parts: string[] = date.trim().split('-')
    if (parts.length === 2 || parts.length === 3) {
      const month: number = Number(parts[parts.length - 2])
      const day: number = Number(parts[parts.length - 1])
      if (parts.some(part => !/^\d+$/.test(part))) return false
      return (parts.length !== 3 || Number(parts[0]) === now.getFullYear()) && month === now.getMonth() + 1 && day === now.getDate()
    }
    if (lunar.leap) return false
    if (date === '除夕') return lunar.eve
    if (date === '春节') return lunar.month === 1 && lunar.day === 1
    if (date === '元宵节' || date === '元宵') return lunar.month === 1 && lunar.day === 15
    if (date === '端午节' || date === '端午') return lunar.month === 5 && lunar.day === 5
    if (date === '七夕') return lunar.month === 7 && lunar.day === 7
    if (date === '中秋节' || date === '中秋') return lunar.month === 8 && lunar.day === 15
    if (date === '重阳节' || date === '重阳') return lunar.month === 9 && lunar.day === 9
    return false
  }

  static resource(now: Date, lunar: CampusLunarDate): Resource {
    if (lunar.eve) return $r('app.string.campus_welcome_lunar_eve')
    if (!lunar.leap && lunar.month === 1 && lunar.day === 1) return $r('app.string.campus_welcome_spring')
    if (!lunar.leap && lunar.month === 1 && lunar.day === 15) return $r('app.string.campus_welcome_lantern')
    if (!lunar.leap && lunar.month === 5 && lunar.day === 5) return $r('app.string.campus_welcome_dragon')
    if (!lunar.leap && lunar.month === 8 && lunar.day === 15) return $r('app.string.campus_welcome_midautumn')
    if (now.getMonth() === 0 && now.getDate() === 1) return $r('app.string.campus_welcome_new_year')
    if (now.getMonth() === 4 && now.getDate() === 1) return $r('app.string.campus_welcome_labour')
    if (now.getMonth() === 8 && now.getDate() === 10) return $r('app.string.campus_welcome_teachers')
    if (now.getMonth() === 9 && now.getDate() <= 7) return $r('app.string.campus_welcome_national_day')
    return CampusGreeting.timeResource(now)
  }

  /** Upstream time phrases remain available even during a holiday. */
  static timeResource(now: Date): Resource {
    const hour: number = now.getHours()
    if (hour >= 23 || hour <= 4) return $r('app.string.campus_welcome_late')
    if (hour <= 8) return $r('app.string.campus_welcome_morning')
    if (hour <= 11) return $r('app.string.campus_welcome_noon')
    if (hour <= 16) return $r('app.string.campus_welcome_afternoon')
    return $r('app.string.campus_welcome_evening')
  }

  static period(now: Date): string {
    return String(now.getFullYear()) + '-' + String(now.getMonth()) + '-' + String(now.getDate()) + ':' +
      (now.getHours() >= 23 || now.getHours() <= 4 ? 'late' : now.getHours() <= 8 ? 'morning' :
        now.getHours() <= 11 ? 'noon' : now.getHours() <= 16 ? 'afternoon' : 'evening')
  }

  /** A stable pool: original time phrase, valid local holiday and all current
   * official greetings. Rotation belongs to deliberate page/refresh events,
   * never a timer that rearranges text while someone is reading. */
  static pool(now: Date, revision: number): string[] {
    const lunar: CampusLunarDate = CampusGreeting.lunar(now)
    const words: string[] = [AppLanguage.text(CampusGreeting.timeResource(now), revision)]
    const holiday: string = AppLanguage.text(CampusGreeting.resource(now, lunar), revision)
    if (holiday && !words.includes(holiday)) words.push(holiday)
    const configuration = AnnouncementConfig.peek()
    const age: number = Date.now() - configuration.cachedAt
    if (configuration.cachedAt > 0 && Number.isFinite(age) && age >= -60000 && age <= 7 * 86400000) {
      for (const celebration of configuration.celebrations) {
        if (CampusGreeting.matches(celebration.date, now, lunar)) {
          for (const word of celebration.words) {
            const trimmed: string = word.trim()
            if (trimmed && !words.includes(trimmed)) words.push(trimmed)
          }
        }
      }
    }
    return words
  }

  static text(now: Date, revision: number, rotation: number = 0): string {
    const words: string[] = CampusGreeting.pool(now, revision)
    const index: number = Number.isFinite(rotation) ? Math.max(0, Math.floor(rotation)) : 0
    return words[index % words.length]
  }
}
