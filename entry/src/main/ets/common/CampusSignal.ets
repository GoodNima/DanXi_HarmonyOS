/** Signals describe verified campus data, independently of locale and display text. */
export class CampusSignal {
  static amount(value: string, low: number = 20): string {
    const raw: string = value.trim().replace(/^[¥￥\s]+/, '').replace(/\s*kWh$/i, '').trim()
    if (!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(raw)) return ''
    const amount: number = Number(raw)
    if (!Number.isFinite(amount)) return ''
    return amount <= 0 ? 'critical' : amount < low ? 'warning' : 'normal'
  }
  static dining(current: number, maximum: number): string {
    if (!Number.isFinite(current) || !Number.isFinite(maximum) || current < 0 || maximum <= 0) return ''
    const ratio: number = current / maximum
    return ratio >= 0.8 ? 'critical' : ratio >= 0.5 ? 'warning' : 'normal'
  }
  static classrooms(free: number, known: number): string {
    return known <= 0 ? '' : free > 0 ? 'normal' : 'warning'
  }
  static permission(value: string): string {
    // Official values include campus lists, e.g. 是(江湾;邯郸). Unknown is not denial.
    const permission: string = value.trim()
    return /^是(?:$|[（(\s])/.test(permission) ? 'normal' : /^否(?:$|[（(\s])/.test(permission) ? 'critical' : ''
  }
  static permissions(values: string[]): string {
    // Follow the original dashboard's aggregate card status. One denied card
    // takes precedence; incomplete records never become an allowed symbol.
    if (values.length === 0) return ''
    const states: string[] = values.map((value: string): string => CampusSignal.permission(value))
    return states.includes('critical') ? 'critical' : states.every((state: string): boolean => state === 'normal') ? 'normal' : ''
  }
}
