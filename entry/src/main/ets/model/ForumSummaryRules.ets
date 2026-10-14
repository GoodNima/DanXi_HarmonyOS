import { ForumSummary, ForumDetailSource, SummaryBranch, SummaryInteraction } from './ForumDetail'
import { ForumFloor } from './Forum'

/** Original ai_summary_sheet.dart protocol: 1001 queued, 1002 processing,
 * 1000 complete. Code 0 is accepted for older compatible servers. */
export class ForumSummaryRules {
  static hasContent(value: ForumSummary | null): boolean {
    return value !== null && (value.summary.trim().length > 0 || value.keywords.length > 0 ||
      value.branches.length > 0 || value.interactions.length > 0)
  }

  static phase(value: ForumSummary): string {
    if (value.code === 1001) return 'queued'
    if (value.code === 1002) return 'processing'
    if (value.code === 1000 || value.code === 0) return ForumSummaryRules.hasContent(value) ? 'ready' : 'empty'
    if (value.code === 2001) return 'empty'
    if (value.code === 2002) return 'unsupported'
    return 'error'
  }

  static waiting(phase: string): boolean { return ['loading', 'queued', 'processing'].includes(phase) }

  static copy(value: ForumSummary | null): string {
    if (value === null) return ''
    return [value.keywords.join(' · '), value.summary,
      value.branches.map((branch: SummaryBranch) => branch.label + '\n' + branch.content + '\n' + branch.floors.map((id: number) => '#' + id).join(' ')).join('\n\n'),
      value.interactions.map((item: SummaryInteraction) => item.fromUser + ' → ' + item.toUser + '\n' + item.content).join('\n\n')]
      .filter((text: string) => text.trim().length > 0).join('\n\n')
  }

  static status(phase: string): Resource {
    switch (phase) {
      case 'queued': return $r('app.string.summary_queued')
      case 'processing': return $r('app.string.summary_processing')
      case 'empty': return $r('app.string.summary_empty')
      case 'unsupported': return $r('app.string.summary_unsupported')
      case 'permission': return $r('app.string.summary_permission')
      case 'timeout': return $r('app.string.summary_timeout')
      case 'error': return $r('app.string.summary_error')
      default: return $r('app.string.summary_loading')
    }
  }

  static interaction(kind: string): Resource {
    switch (kind.toLowerCase()) {
      case 'support': return $r('app.string.summary_support')
      case 'rebuttal': return $r('app.string.summary_rebuttal')
      case 'supplement': return $r('app.string.summary_supplement')
      case 'question': return $r('app.string.summary_question')
      default: return $r('app.string.summary_reply')
    }
  }

  static color(value: string, dark: boolean): string {
    // Server colors may be arbitrarily dark/light. Blend toward the theme's
    // readable foreground to preserve each branch hue in both appearances.
    if (!/^#?[0-9a-fA-F]{6}$/.test(value)) return dark ? '#80BFFF' : '#2479AE'
    const hex: string = value.replace('#', '')
    const channels: number[] = [0, 2, 4].map((start: number) => Number.parseInt(hex.substring(start, start + 2), 16))
    return '#' + channels.map((channel: number) => Math.round(dark ? channel * 0.6 + 102 : channel * 0.75)
      .toString(16).padStart(2, '0')).join('')
  }

  static interactionColor(kind: string, dark: boolean): string {
    switch (kind.toLowerCase()) {
      case 'support': return dark ? '#FF9EAE' : '#B52B4A'
      case 'rebuttal': case 'question': return dark ? '#FFC175' : '#995300'
      case 'supplement': return dark ? '#7EDCB0' : '#19764C'
      default: return dark ? '#80BFFF' : '#2479AE'
    }
  }

  /** Match IDs first as upstream does, then a 1-based ordinal. Fetch only
   * one row for the fallback instead of loading every floor in a long thread. */
  static async resolve(source: ForumDetailSource, hole: number, id: number, total: number,
    current: () => boolean): Promise<ForumFloor> {
    let failure: Error | null = null
    try {
      const floor: ForumFloor = await source.getFloor(id)
      if (!current()) throw new Error('Obsolete summary location')
      if (floor.holeId === hole) return floor
    } catch (e) { if (!current()) throw new Error('Obsolete summary location'); failure = e instanceof Error ? e : new Error(String(e)) }
    if (id > 0 && id <= total) {
      const rows: ForumFloor[] = await source.getFloors(hole, id - 1, 1)
      if (!current()) throw new Error('Obsolete summary location')
      if (rows.length > 0 && rows[0].holeId === hole) return rows[0]
    }
    if (failure !== null) throw failure
    throw new Error('Summary floor is unavailable (reference ' + id + ')')
  }
}
