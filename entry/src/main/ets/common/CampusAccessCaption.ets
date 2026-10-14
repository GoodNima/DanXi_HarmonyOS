export class CampusAccessLine {
  permission: string = ''
  campuses: string[] = []
  fallback: string = ''
  constructor(permission: string, campuses: string[], fallback: string = '') {
    this.permission = permission; this.campuses = campuses; this.fallback = fallback
  }
}

/** Keep each official campus name together when an access caption wraps. */
export class CampusAccessCaption {
  static smallLines(value: string, maximum: number): CampusAccessLine[] {
    const records: string[] = value.trim().split(/\s+\/\s+/).filter((record: string): boolean => record.length > 0)
    // A restricted record explains the aggregate cross; retain each record's own campuses.
    const ordered: string[] = records.filter((record: string): boolean => /^否(?:$|[（(\s])/.test(record))
      .concat(records.filter((record: string): boolean => !/^否(?:$|[（(\s])/.test(record)))
    const lines: CampusAccessLine[] = []
    for (const record of ordered) {
      const match: RegExpExecArray | null = /^([是否])\s*(?:[（(]([^（）()]*)[）)])?$/.exec(record.trim())
      if (match === null) { lines.push(new CampusAccessLine('', [], record)); continue }
      const campuses: string[] = (match[2] ?? '').split(/[;；、,，]/).map((campus: string): string => campus.trim())
        .filter((campus: string): boolean => campus.length > 0)
      if (campuses.length === 0) { lines.push(new CampusAccessLine(match[1], [])); continue }
      for (let index: number = 0; index < campuses.length; index += 2) {
        lines.push(new CampusAccessLine(index === 0 ? match[1] : '', campuses.slice(index, index + 2)))
      }
    }
    if (lines.length <= maximum) return lines
    // Small summaries are bounded; the card opens the complete access details.
    return lines.slice(0, Math.max(0, maximum - 1)).concat([new CampusAccessLine('', [], '…')])
  }

  static tokens(value: string): string[] {
    const tokens: string[] = []
    const records: string[] = value.trim().split(/\s+\/\s+/).filter((record: string): boolean => record.length > 0)
    for (let recordIndex: number = 0; recordIndex < records.length; recordIndex++) {
      if (recordIndex > 0) tokens.push(' / ')
      const record: string = records[recordIndex].trim()
      const match: RegExpExecArray | null = /^([是否])\s*(?:[（(]([^（）()]*)[）)])?$/.exec(record)
      if (match === null || !match[2]) {
        tokens.push(record)
        continue
      }
      const campuses: string[] = match[2].split(/[;；、,，]/).map((campus: string): string => campus.trim())
        .filter((campus: string): boolean => campus.length > 0)
      if (campuses.length === 0) {
        tokens.push(match[1])
        continue
      }
      tokens.push(match[1] + ' · ')
      for (let campusIndex: number = 0; campusIndex < campuses.length; campusIndex++) {
        tokens.push(campuses[campusIndex] + (campusIndex < campuses.length - 1 ? '、' : ''))
      }
    }
    return tokens
  }
}
