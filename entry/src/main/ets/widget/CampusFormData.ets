/** Small, credential-free snapshots shared with the system form renderer. */
export class CampusFormRow {
  label: string = ''
  value: string = ''
  detail: string = ''
}

export class CampusFormData {
  dimension: number = 2
  feature: string = 'timetable'
  value: string = ''
  description: string = ''
  secondary: string = ''
  tone: string = ''
  updatedAt: number = 0
  updatedLabel: string = ''
  stale: boolean = false
  rows: CampusFormRow[] = []

  static supports(feature: string): boolean { return ['timetable', 'card', 'electricity', 'bus'].includes(feature) }
  static empty(feature: string): CampusFormData {
    const data = new CampusFormData(); data.feature = CampusFormData.supports(feature) ? feature : 'timetable'; return data
  }
  static read(raw: string, feature: string, now: number = Date.now()): CampusFormData {
    try {
      const saved: CampusFormData = JSON.parse(raw) as CampusFormData
      if (saved.feature !== feature || !CampusFormData.supports(feature) ||
        typeof saved.value !== 'string' || typeof saved.description !== 'string' || typeof saved.secondary !== 'string' ||
        !Number.isFinite(saved.updatedAt) || saved.updatedAt <= 0 || saved.updatedAt > now + 60000) return CampusFormData.empty(feature)
      const data = CampusFormData.empty(feature)
      data.value = saved.value; data.description = saved.description; data.secondary = saved.secondary
      data.tone = ['normal', 'warning', 'critical'].includes(saved.tone) ? saved.tone : ''
      data.updatedAt = saved.updatedAt
      const date = new Date(saved.updatedAt)
      data.updatedLabel = String(date.getMonth() + 1) + '/' + String(date.getDate()) + ' ' +
        String(date.getHours()).padStart(2, '0') + ':' + String(date.getMinutes()).padStart(2, '0')
      data.stale = now - saved.updatedAt > ((feature === 'bus' || feature === 'timetable') ? 30 * 60000 : 6 * 3600000)
      if (Array.isArray(saved.rows)) data.rows = saved.rows.filter(row => row && typeof row.label === 'string' &&
        typeof row.value === 'string' && typeof row.detail === 'string').slice(0, 6)
      // Do not present yesterday's timetable or departed buses as current.
      if ((feature === 'bus' || feature === 'timetable') && date.toDateString() !== new Date(now).toDateString()) {
        data.value = ''; data.description = ''; data.rows = []
      }
      return data
    } catch (e) { return CampusFormData.empty(feature) }
  }
}
