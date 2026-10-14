/** Structured rows derived from a single existing campus service snapshot. */
export class CampusPreviewItem {
  tone: string = ''
  label: string = ''
  value: string = ''
  detail: string = ''

  static copy(items: CampusPreviewItem[] | undefined): CampusPreviewItem[] {
    if (!Array.isArray(items)) return []
    const rows: CampusPreviewItem[] = []
    for (const item of items.slice(0, 8)) {
      if (item === null || item === undefined || typeof item.label !== 'string' || typeof item.value !== 'string' || typeof item.detail !== 'string') continue
      const row = new CampusPreviewItem(); row.label = item.label; row.value = item.value; row.detail = item.detail
      row.tone = ['normal', 'warning', 'critical'].includes(item.tone) ? item.tone : ''
      rows.push(row)
    }
    return rows
  }
}
