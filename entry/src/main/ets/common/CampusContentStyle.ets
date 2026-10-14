import { EmptyClassroom } from '../model/Academic'
import { ThemeColors } from './Theme'

/** Readable semantic emphasis in both themes; server display values stay untouched. */
export class CampusContentStyle {
  static readonly accent: ResourceColor = $r('app.color.campus_text_accent')
  static readonly available: ResourceColor = $r('app.color.campus_text_available')
  static readonly attention: ResourceColor = $r('app.color.campus_text_attention')
  static readonly warning: ResourceColor = $r('app.color.campus_text_warning')
  static readonly highlight: ResourceColor = $r('app.color.campus_highlight')

  static signalColor(tone: string, fallback: ResourceColor): ResourceColor {
    return tone === 'normal' ? CampusContentStyle.available : tone === 'warning' ? CampusContentStyle.warning :
      tone === 'critical' ? CampusContentStyle.attention : fallback
  }

  static classroomColor(item: EmptyClassroom): ResourceColor {
    // A legacy status string has no availability contract: never guess from its wording.
    return item.freePeriods !== undefined && item.freePeriods.length > 0 ? CampusContentStyle.available : ThemeColors.textSecondary
  }

  static classroomSurface(item: EmptyClassroom): ResourceColor {
    return item.freePeriods !== undefined && item.freePeriods.length > 0 ?
      $r('app.color.campus_available_surface') : $r('app.color.input_surface')
  }

  static gradeColor(level: string): ResourceColor {
    // Only explicit published fail/no-pass marks receive attention. Do not derive grades from GPA or numbers.
    const mark = level.trim().toUpperCase()
    return mark === 'F' || mark === 'NP' || mark === '不及格' || mark === '不通过' ?
      CampusContentStyle.attention : CampusContentStyle.accent
  }
}
