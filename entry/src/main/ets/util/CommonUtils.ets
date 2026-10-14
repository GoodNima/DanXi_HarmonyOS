/**
 * Common utility functions.
 */

export class StringUtils {
  static isEmpty(str: string | null | undefined): boolean {
    return str === null || str === undefined || str.length === 0
  }

  static isNotEmpty(str: string | null | undefined): boolean {
    return !StringUtils.isEmpty(str)
  }

  static truncate(str: string, maxLength: number): string {
    if (str.length <= maxLength) return str
    return str.substring(0, maxLength) + '...'
  }

  static capitalize(str: string): string {
    if (str.length === 0) return str
    return str.charAt(0).toUpperCase() + str.slice(1)
  }
}

export class DateTimeUtils {
  static formatTime(timestamp: number): string {
    const date = new Date(timestamp)
    const now = new Date()
    const diffMs = now.getTime() - date.getTime()
    const diffMin = Math.floor(diffMs / 60000)
    const diffHour = Math.floor(diffMin / 60)
    const diffDay = Math.floor(diffHour / 24)

    if (diffMin < 1) return '刚刚'
    if (diffMin < 60) return diffMin + '分钟前'
    if (diffHour < 24) return diffHour + '小时前'
    if (diffDay < 7) return diffDay + '天前'
    return DateTimeUtils.formatDate(timestamp)
  }

  static formatDate(timestamp: number): string {
    const date = new Date(timestamp)
    return date.getFullYear() + '-' + String(date.getMonth() + 1).padStart(2, '0') + '-' + String(date.getDate()).padStart(2, '0')
  }

  static formatDateTime(timestamp: number): string {
    const date = new Date(timestamp)
    return DateTimeUtils.formatDate(timestamp) + ' ' + String(date.getHours()).padStart(2, '0') + ':' + String(date.getMinutes()).padStart(2, '0')
  }

  static getTodayWeekday(): number {
    const day = new Date().getDay()
    return day === 0 ? 7 : day
  }

  static getWeekdayName(weekday: number): string {
    const names: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日']
    if (weekday >= 1 && weekday <= 7) return names[weekday - 1]
    return ''
  }
}

export class MathUtils {
  static clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value))
  }

  static round(value: number, decimals: number = 2): number {
    const factor = Math.pow(10, decimals)
    return Math.round(value * factor) / factor
  }
}
