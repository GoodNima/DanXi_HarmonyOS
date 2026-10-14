import { DiningTraffic } from '../model/CampusLiveData'

/** Presentation of every server window; aliases never remove or merge source rows. */
export class DiningPresentation {
  static zone(name: string, campus: string): string {
    const label: string = name.replace(/\\n|\r?\n/g, '-').trim()
    if (/文图咖啡|^文科图书馆/.test(label)) return '文科图书馆'
    if (/^光华/.test(label)) return '光华楼'
    if (/^北区/.test(label)) return '北区食堂'
    if (/^南苑/.test(label) || (/^南区/.test(label) && label.includes('南苑'))) return '南苑食堂'
    if (/^南区/.test(label) && label.includes('教工')) return '南区教工食堂'
    if (/^南区/.test(label)) return '南区食堂'
    if (/^旦苑/.test(label)) return '旦苑食堂'
    if (/^二号书院楼/.test(label)) return '二号书院楼'
    if (/^书院楼/.test(label)) return '书院楼'
    if (/^护理学院/.test(label)) return '护理学院'
    if (/^枫林(?:清真|民族)餐厅/.test(label)) return '枫林清真餐厅'
    if (/^枫林食堂/.test(label)) return '枫林食堂'
    if (/^江湾北食堂/.test(label)) return '江湾北食堂'
    if (/^江湾.*光华.*Mall/i.test(label)) return '江湾光华 Mall 食堂'
    if (campus === '江湾' && /^一食堂/.test(label)) return '江湾一食堂'
    if (/^图书馆.*咖啡/.test(label)) return '图书馆咖啡厅'
    if (/^物理楼.*咖啡/.test(label)) return '物理楼咖啡厅'
    if (/^花园餐厅/.test(label)) return '花园餐厅'
    const separator: number = label.indexOf('-')
    return separator > 0 ? label.substring(0, separator) : campus
  }

  static windowName(item: DiningTraffic): string {
    const separator: number = item.name.indexOf('-')
    // Only remove a location prefix when it is already the visible heading.
    // Internal hyphens in a standalone window name remain intact.
    if (separator > 0 && DiningPresentation.zone(item.name.substring(0, separator), item.zone) === item.zone) {
      return item.name.substring(separator + 1).trim() || item.name
    }
    return item.name
  }

  static coffee(zone: string): boolean { return /咖啡|光华楼|文科图书馆/.test(zone) }

  static ratios(items: DiningTraffic[]): DiningTraffic[] {
    const windows: DiningTraffic[] = items.filter((item: DiningTraffic): boolean =>
      Number.isFinite(item.current) && item.current >= 0 && Number.isFinite(item.maximum) && item.maximum > 0)
    // Compare individual windows against their own peak; a zero-count window
    // is available when other windows are active. An all-zero feed is inactive.
    if (!windows.some((item: DiningTraffic): boolean => item.current > 0)) return []
    return windows
      .sort((a: DiningTraffic, b: DiningTraffic): number => a.ratio() - b.ratio())
  }
}
