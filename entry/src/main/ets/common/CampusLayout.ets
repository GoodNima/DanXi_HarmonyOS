import { Constant } from './Constant'

export interface CampusModule {
  id: string
  enabled: boolean
  size?: string
  row?: number
  column?: number
}

export interface CampusCardPlacement {
  module: CampusModule
  row: number
  column: number
  rowSpan: number
  columnSpan: number
}

export class CampusGridPlan {
  cards: CampusCardPlacement[] = []
  rowCount: number = 0

  height(): number {
    return this.rowCount > 0 ? this.rowCount * CampusLayout.HALF_HEIGHT +
      (this.rowCount - 1) * CampusLayout.CARD_GAP : 0
  }

  template(): string {
    const tracks: string[] = []
    // The fixed board height subtracts all gaps before equal fractional rows.
    // Unitless fixed tracks collapse to one row on the current native engine.
    for (let row: number = 0; row < this.rowCount; row++) tracks.push('1fr')
    return tracks.join(' ')
  }
}

/** Feature IDs remain independent of UI language and network payloads. */
export class CampusLayout {
  static readonly CARD_GAP: number = 12
  static readonly HALF_HEIGHT: number = 88
  static readonly FULL_HEIGHT: number = 188

  /** A half-height lattice fills earlier holes without changing the saved order.
   * Full-width cards delimit groups, so later cards never jump over a heading.
   * The editor and home use the same stable plan and the same actual hit bounds. */
  static pack(rows: CampusModule[]): CampusGridPlan {
    const plan: CampusGridPlan = new CampusGridPlan()
    const occupied: boolean[] = []
    // Reserve explicitly placed cards first; automatic packing fills real gaps.
    for (const module of rows) {
      if (!module.enabled || !CampusLayout.positioned(module)) continue
      const span: number = CampusLayout.large(module) ? 2 : 1
      const height: number = CampusLayout.compact(module) ? 1 : 2
      const row: number = module.row ?? 0
      const column: number = module.column ?? 0
      let available: boolean = column + span <= 2
      for (let y: number = row; y < row + height; y++) {
        for (let x: number = column; x < column + span; x++) if (occupied[y * 2 + x]) available = false
      }
      if (!available) continue
      for (let y: number = row; y < row + height; y++) {
        for (let x: number = column; x < column + span; x++) occupied[y * 2 + x] = true
      }
      plan.cards.push({ module: module, row: row, column: column, rowSpan: height, columnSpan: span })
      plan.rowCount = Math.max(plan.rowCount, row + height)
    }
    let startRow: number = 0
    for (const module of rows) {
      if (!module.enabled || plan.cards.some((card: CampusCardPlacement) => card.module.id === module.id)) continue
      const columnSpan: number = CampusLayout.large(module) ? 2 : 1
      const rowSpan: number = CampusLayout.compact(module) ? 1 : 2
      let row: number = columnSpan === 2 ? plan.rowCount : startRow
      let column: number = 0
      let found: boolean = false
      while (!found) {
        for (column = 0; column <= 2 - columnSpan; column++) {
          let available: boolean = true
          for (let y: number = row; y < row + rowSpan; y++) {
            for (let x: number = column; x < column + columnSpan; x++) {
              if (occupied[y * 2 + x]) available = false
            }
          }
          if (available) { found = true; break }
        }
        if (!found) row++
      }
      for (let y: number = row; y < row + rowSpan; y++) {
        for (let x: number = column; x < column + columnSpan; x++) occupied[y * 2 + x] = true
      }
      plan.cards.push({ module: module, row: row, column: column, rowSpan: rowSpan, columnSpan: columnSpan })
      plan.rowCount = Math.max(plan.rowCount, row + rowSpan)
      if (columnSpan === 2) startRow = plan.rowCount
    }
    return plan
  }

  static defaults(): CampusModule[] {
    return Constant.DEFAULT_DASHBOARD_ORDER.map((id: string): CampusModule =>
      ({ id: id, enabled: true, size: CampusLayout.defaultSize(id) }))
  }

  /** Full-width anchors and square + stacked half-height cards keep categories
   * together without holes. Common study and daily tasks get the upper slots. */
  private static defaultSize(id: string): string {
    if (id === 'timetable' || id === 'announcement' || id === 'developer_notice') return 'large'
    if (id === 'academic' || id === 'empty_classroom' || id === 'dining' || id === 'sports' || id === 'bus') return 'small'
    return 'compact'
  }

  /** Only an untouched previous recommendation is upgraded. Any saved move,
   * visibility, size or explicit blank-cell placement remains the user's. */
  private static previousDefaults(rows: CampusModule[]): boolean {
    const prior: string[] = ['timetable', 'academic', 'empty_classroom', 'library', 'library_books',
      'announcement', 'card', 'electricity', 'dining', 'sports', 'bus', 'campus_access', 'life_code', 'developer_notice']
    if (rows.length === prior.length && rows.every((row: CampusModule, index: number) =>
      row.id === prior[index] && row.enabled && row.row === undefined && row.column === undefined &&
      row.size === CampusLayout.defaultSize(row.id))) return true
    // The v112 recommendation predates the new books card. Do not move a
    // customized layout when introducing that feature.
    const recent: string[] = prior.filter((id: string) => id !== 'library_books')
    if (rows.length === recent.length && rows.every((row: CampusModule, index: number) =>
      row.id === recent[index] && row.enabled && row.row === undefined && row.column === undefined &&
      row.size === (row.id === 'empty_classroom' ? 'compact' : CampusLayout.defaultSize(row.id)))) return true
    const ids: string[] = ['timetable', 'card', 'life_code', 'bus', 'empty_classroom', 'library', 'dining',
      'announcement', 'academic', 'sports', 'electricity', 'campus_access', 'developer_notice']
    if (rows.length !== ids.length) return false
    for (let i: number = 0; i < ids.length; i++) {
      const id: string = ids[i]
      const size: string = id === 'timetable' || id === 'announcement' ? 'large' :
        ['bus', 'empty_classroom', 'academic', 'sports'].includes(id) ? 'small' : 'compact'
      if (rows[i].id !== id || !rows[i].enabled || rows[i].size !== (id === 'developer_notice' ? 'large' : size) ||
        rows[i].row !== undefined || rows[i].column !== undefined) return false
    }
    return true
  }

  static parse(json: string): CampusModule[] {
    const rows: CampusModule[] = []
    try {
      // Migrate the previous string[] preference and merge newly supported features.
      const raw = JSON.parse(json) as (string | CampusModule)[]
      if (Array.isArray(raw)) {
        const explicitAcademic = raw.find((entry: string | CampusModule) =>
          (typeof entry === 'string' ? entry : entry?.id) === Constant.FEATURE_ACADEMIC)
        for (const entry of raw) {
          const originalId = typeof entry === 'string' ? entry : entry?.id
          if (typeof originalId !== 'string') continue
          const legacyAcademic = originalId === Constant.FEATURE_EXAM || originalId === Constant.FEATURE_GPA
          const id = legacyAcademic ? Constant.FEATURE_ACADEMIC : originalId
          if (!Constant.DEFAULT_DASHBOARD_ORDER.includes(id)) continue
          if (legacyAcademic && explicitAcademic !== undefined) continue
          const enabled = typeof entry === 'string' || entry.enabled !== false
          const previous = rows.find((row: CampusModule) => row.id === id)
          if (previous !== undefined) {
            // Preserve the earliest old position and either old module's visibility.
            if (legacyAcademic && enabled) previous.enabled = true
            continue
          }
          const row: CampusModule = { id: id, enabled: enabled }
          if (typeof entry !== 'string' && CampusLayout.validSize(entry.size)) row.size = CampusLayout.supportsSize(id, entry.size ?? '') ? entry.size : (id === 'announcement' || id === 'developer_notice' ? 'large' : 'small')
          if (typeof entry !== 'string' && CampusLayout.positioned(entry)) {
            row.row = entry.row; row.column = entry.column
          }
          rows.push(row)
        }
      }
    } catch (e) { /* Corrupt preferences fall back to the supported modules. */ }
    if (rows.length === 0) return CampusLayout.defaults()
    if (CampusLayout.previousDefaults(rows)) return CampusLayout.defaults()
    // Preserve saved choices, including legacy entries without an explicit size.
    // Only newly supported modules inherit the current recommendation.
    for (const row of CampusLayout.defaults()) {
      if (!rows.some((saved: CampusModule) => saved.id === row.id)) rows.push(CampusLayout.copy(row))
    }
    if (!rows.some((row: CampusModule) => row.enabled)) rows[0].enabled = true
    return rows
  }

  static move(rows: CampusModule[], from: number, to: number): CampusModule[] {
    const result = rows.map((row: CampusModule): CampusModule => ({ id: row.id, enabled: row.enabled, size: row.size }))
    if (!Number.isInteger(from) || !Number.isInteger(to) || from < 0 || from >= rows.length ||
      to < 0 || to >= rows.length) return result
    const moved = result.splice(from, 1)[0]
    result.splice(to, 0, moved)
    return result
  }

  static copy(row: CampusModule): CampusModule {
    const copy: CampusModule = { id: row.id, enabled: row.enabled }
    if (CampusLayout.validSize(row.size)) copy.size = CampusLayout.supportsSize(row.id, row.size ?? '') ? row.size : (row.id === 'announcement' || row.id === 'developer_notice' ? 'large' : 'small')
    if (CampusLayout.positioned(row)) { copy.row = row.row; copy.column = row.column }
    return copy
  }

  private static positioned(row: CampusModule): boolean {
    return Number.isInteger(row.row) && (row.row ?? -1) >= 0 && (row.row ?? 0) <= 200 &&
      Number.isInteger(row.column) && (row.column === 0 || row.column === 1)
  }

  /** A blank-cell drop preserves other locations instead of repacking the gap away. */
  static place(rows: CampusModule[], id: string, row: number, column: number): CampusModule[] {
    const plan: CampusGridPlan = CampusLayout.pack(rows)
    const moving: CampusCardPlacement | undefined = plan.cards.find((card: CampusCardPlacement) => card.module.id === id)
    if (moving === undefined || !Number.isInteger(row) || row < 0 || row > Math.min(200, plan.rowCount + 2) ||
      !Number.isInteger(column) || column < 0 || column + moving.columnSpan > 2) return rows.map((item: CampusModule) => CampusLayout.copy(item))
    if (plan.cards.some((card: CampusCardPlacement) => card.module.id !== id &&
      row < card.row + card.rowSpan && row + moving.rowSpan > card.row &&
      column < card.column + card.columnSpan && column + moving.columnSpan > card.column)) return rows.map((item: CampusModule) => CampusLayout.copy(item))
    return rows.map((item: CampusModule): CampusModule => {
      const copy: CampusModule = CampusLayout.copy(item)
      const placement: CampusCardPlacement | undefined = plan.cards.find((card: CampusCardPlacement) => card.module.id === item.id)
      if (placement !== undefined) { copy.row = item.id === id ? row : placement.row; copy.column = item.id === id ? column : placement.column }
      return copy
    })
  }

  private static validSize(size: string | undefined): boolean {
    return size === 'compact' || size === 'small' || size === 'large'
  }

  static supportsSize(id: string, size: string): boolean {
    if (id === 'announcement' || id === 'developer_notice') return size === 'large'
    return CampusLayout.validSize(size) && (size !== 'large' || !['campus_access', 'life_code', 'card', 'electricity', 'library_books', 'sports'].includes(id))
  }

  /** Missing or invalid preferences retain each module's original default size. */
  static size(row: CampusModule): string {
    if (row.size !== undefined && CampusLayout.validSize(row.size)) return CampusLayout.supportsSize(row.id, row.size) ? row.size : (row.id === 'announcement' || row.id === 'developer_notice' ? 'large' : 'small')
    return ['announcement', 'timetable', 'academic', 'developer_notice', 'evaluation'].includes(row.id) ? 'large' : 'small'
  }

  static compact(row: CampusModule): boolean {
    return CampusLayout.size(row) === 'compact'
  }

  /** Add a short unit only to bare numeric data; do not duplicate a service's
   * unit or reinterpret a permission state, clock time or error message. */
  static metric(value: string, unit: string): string {
    const text: string = value.trim()
    return unit && /^[+-]?\d[\d,.]*$/.test(text) ? text + ' ' + unit : value
  }

  static unit(id: string): Resource | undefined {
    if (id === 'card') return $r('app.string.campus_unit_cny')
    if (id === 'library') return $r('app.string.campus_unit_people')
    if (id === 'electricity') return $r('app.string.campus_unit_kwh')
    if (id === 'empty_classroom') return $r('app.string.campus_unit_rooms')
    return undefined
  }

  static hint(id: string): Resource {
    switch (id) {
      case 'announcement': return $r('app.string.campus_hint_announcement')
      case 'bus': return $r('app.string.campus_hint_bus')
      case 'empty_classroom': return $r('app.string.campus_hint_empty_classroom')
      case 'academic': return $r('app.string.campus_hint_academic')
      case 'timetable': return $r('app.string.campus_hint_timetable')
      case 'evaluation': return $r('app.string.campus_hint_evaluation')
      case 'campus_access': return $r('app.string.campus_hint_campus_access')
      case 'sports': return $r('app.string.campus_hint_sports')
      case 'life_code': return $r('app.string.campus_hint_life_code')
      case 'developer_notice': return $r('app.string.campus_hint_developer_notice')
      case 'dining': return $r('app.string.campus_hint_dining')
      case 'library': return $r('app.string.campus_hint_library')
      case 'library_books': return $r('app.string.campus_hint_library_books')
      case 'electricity': return $r('app.string.campus_hint_electricity')
      default: return $r('app.string.campus_hint_card')
    }
  }

  static large(row: CampusModule): boolean {
    return CampusLayout.size(row) === 'large'
  }

  /** Short balances/counts and permission states are the card's visual anchor.
   * The shared single-line preview adapts down from this preferred font size. */
  static keyFont(row: CampusModule, value: string): number {
    const length: number = value.trim().length
    const numeric: boolean = /^[\d.,+-]+(?:\s*(?:[元人度次%间間室]|CNY|kWh|people|rooms)|\s*\/\s*[\d.,]+)?$/.test(value.trim()) || /^\d{1,2}:\d{2}$/.test(value.trim())
    if (CampusLayout.compact(row)) return numeric || /^[\d.,+-]+\s*间$/.test(value.trim()) ? 20 : 18
    if (row.id === 'announcement' || row.id === 'developer_notice' || length > 28) return CampusLayout.large(row) ? 22 : 20
    // Keep the classroom count and its short unit together in half-width cards.
    // Native text adaptation may shrink this slightly on narrow screens.
    if (row.id === 'empty_classroom' && !CampusLayout.large(row)) return 22
    if (numeric) return 30
    return length <= 12 ? 26 : 23
  }

  /** The catalogue owns sizing. One module stays one card, even when all three
   * sizes are offered; adding a hidden card places it after visible cards. */
  static choose(rows: CampusModule[], id: string, size: string): CampusModule[] {
    const result: CampusModule[] = rows.map((row: CampusModule): CampusModule => CampusLayout.copy(row))
    if (!CampusLayout.supportsSize(id, size)) return result
    const index: number = result.findIndex((row: CampusModule) => row.id === id)
    if (index < 0) return result
    const chosen: CampusModule = result[index]
    const hidden: boolean = !chosen.enabled
    chosen.enabled = true
    chosen.size = size
    chosen.row = undefined; chosen.column = undefined
    if (hidden) {
      result.splice(index, 1)
      result.push(chosen)
    }
    return result
  }

  static title(id: string): Resource {
    switch (id) {
      case 'announcement': return $r('app.string.feature_announcement')
      case 'bus': return $r('app.string.feature_bus')
      case 'empty_classroom': return $r('app.string.feature_empty_classroom')
      case 'academic': return $r('app.string.feature_academic')
      case 'exam': return $r('app.string.feature_exam')
      case 'gpa': return $r('app.string.feature_gpa')
      case 'timetable': return $r('app.string.feature_timetable')
      case 'evaluation': return $r('app.string.feature_evaluation')
      case 'campus_access': return $r('app.string.feature_campus_access')
      case 'sports': return $r('app.string.feature_sports')
      case 'life_code': return $r('app.string.feature_life_code')
      case 'developer_notice': return $r('app.string.feature_developer_notice')
      case 'dining': return $r('app.string.feature_dining')
      case 'library': return $r('app.string.feature_library')
      case 'library_books': return $r('app.string.feature_library_books')
      case 'electricity': return $r('app.string.feature_electricity')
      default: return $r('app.string.feature_card')
    }
  }
}
