/**
 * Dashboard card model - represents a feature card on the dashboard.
 * Ported from lib/model/dashboard_card.dart
 */

export enum DashboardCardType {
  ANNOUNCEMENT = 'announcement',
  BUS = 'bus',
  EMPTY_CLASSROOM = 'empty_classroom',
  EXAM = 'exam',
  GPA = 'gpa',
  TIMETABLE = 'timetable',
  COURSE_REVIEW = 'course_review',
  FORUM = 'forum',
  CELEBRATION = 'celebration',
}

interface DashboardCardJson {
  id: string
  type: DashboardCardType
  title: string
  subtitle: string
  icon: string
  content: string
  timestamp: number
  extra: Record<string, string>
}

export class DashboardCard {
  id: string
  type: DashboardCardType
  title: string
  subtitle: string
  icon: string
  content: string
  timestamp: number
  extra: Map<string, string>

  constructor(type: DashboardCardType, title: string, subtitle: string = '', icon: string = '', content: string = '') {
    this.id = type + '_' + Date.now()
    this.type = type
    this.title = title
    this.subtitle = subtitle
    this.icon = icon
    this.content = content
    this.timestamp = Date.now()
    this.extra = new Map()
  }

  toJson(): string {
    const extraObj: Record<string, string> = {}
    this.extra.forEach((value: string, key: string) => {
      extraObj[key] = value
    })
    const data: DashboardCardJson = {
      id: this.id,
      type: this.type,
      title: this.title,
      subtitle: this.subtitle,
      icon: this.icon,
      content: this.content,
      timestamp: this.timestamp,
      extra: extraObj,
    }
    return JSON.stringify(data)
  }

  static fromJson(json: string): DashboardCard | null {
    try {
      const data: DashboardCardJson = JSON.parse(json) as DashboardCardJson
      const card = new DashboardCard(data.type, data.title, data.subtitle, data.icon, data.content)
      card.id = data.id
      card.timestamp = data.timestamp
      if (data.extra) {
        const keys = Object.keys(data.extra)
        for (const key of keys) {
          card.extra.set(key, data.extra[key])
        }
      }
      return card
    } catch (e) {
      return null
    }
  }
}
