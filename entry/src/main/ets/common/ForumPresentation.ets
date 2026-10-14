import { ForumHole, ForumTag } from '../model/Forum'
import { ForumLocalState } from './ForumLocalState'
import { ForumPreferences } from './ForumPreferences'
import { ForumAuthorPalette } from './ForumAuthorPalette'

/** iOS randomColor uses a UTF-16 sum and a stable nineteen-color palette. */
export class ForumPresentation {
  private static readonly COLORS: string[] = ["#FF3B30","#FF2D55","#AF52DE","#673AB7","#5856D6","#007AFF","#03A9F4","#32ADE6","#30B0C7","#34C759","#72A13E","#26A428","#E8BA11","#E5AD0E","#FF9500","#DD6E0F","#A2845E","#7393B3","#7A7C7C"]
  private static readonly DARK_COLORS: string[] = ["#FF453A","#FF375F","#BF5AF2","#9554FF","#6765FF","#0A84FF","#03A9F4","#64D2FF","#40CBE0","#30D158","#8BC34A","#32CD32","#FFD60A","#FFBF00","#FF9F0A","#FF8611","#AC8E68","#87ACD4","#B3B5B5"]

  static tagLabel(name: string): string { return name.replace(/^#+/, '') }
  static featured(name: string): boolean { return ForumPresentation.tagLabel(name) === '旦挞精选' }
  static tagColor(name: string, dark: boolean = false, highContrast: boolean = false): string {
    if (highContrast) {
      const original: string = ForumPresentation.tagColor(name, dark)
      let result: string = '#'
      for (let i: number = 1; i < 7; i += 2) {
        const channel: number = parseInt(original.substring(i, i + 2), 16)
        result += Math.round(dark ? channel + (255 - channel) * 0.25 : channel * 0.55).toString(16).padStart(2, '0')
      }
      return result
    }
    if (!name || name.startsWith('*')) return dark ? '#FF453A' : '#FF3B30'
    let sum: number = 0
    for (let i: number = 0; i < name.length; i++) sum += name.charCodeAt(i)
    return (dark ? ForumPresentation.DARK_COLORS : ForumPresentation.COLORS)[sum % ForumPresentation.COLORS.length]
  }
  static tagBackground(name: string, dark: boolean = false, highContrast: boolean = false): string {
    return (dark ? '#33' : '#1A') + ForumPresentation.tagColor(name, dark, highContrast).substring(1)
  }
  static authorColor(name: string, dark: boolean = false): string {
    return ForumAuthorPalette.color(name, dark)
  }

  static foldMode(value: string): string {
    return value === 'show' || value === 'hide' ? value : 'fold'
  }

  static isCaution(hole: ForumHole): boolean {
    return hole.tags.some((tag: ForumTag) => tag.name.startsWith('*'))
  }

  static visibleHoles(holes: ForumHole[], mode: string): ForumHole[] {
    const blocked: string[] = ForumPreferences.hiddenTags()
    return holes.filter((hole: ForumHole) => !ForumLocalState.hidden(hole.holeId) &&
      !hole.tags.some((tag: ForumTag) => blocked.includes(tag.name)) &&
      (mode !== 'hide' || !ForumPresentation.isCaution(hole)))
  }

  /** Bound the number of native views when the server returns thousands of tags. */
  static tagSuggestions(tags: ForumTag[], query: string, page: number = 0): ForumTag[] {
    const needle: string = query.trim().toLowerCase()
    const matches: ForumTag[] = tags.filter((tag: ForumTag) => tag.name.toLowerCase().includes(needle))
    return matches.slice(page * 24, (page + 1) * 24)
  }
}
