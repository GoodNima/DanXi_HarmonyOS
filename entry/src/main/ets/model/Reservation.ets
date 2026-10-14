import { CampusHtml, CampusHtmlNode } from './CampusHtml'
import { FduAuthPolicy } from './FduAuth'
import { HttpError } from '../util/HttpUtil'
import { AppLanguage } from '../common/AppLanguage'

export interface Playground {
  id: string
  name: string
  campus: string
  category: string
  categoryId: string
}

export interface ReservationSlot {
  id: string
  name: string
  begin: string
  end: string
  reserved: number
  total: number
  reserveId: string
  categoryId: string
  playgroundId: string
}

/** Exact HTML selectors and booking form used by DanXi Swift ReservationAPI. */
export class ReservationParser {
  static readonly ORIGIN: string = 'https://elife.fudan.edu.cn'
  static readonly CATEGORIES: string[] = ['2c9c486e4f821a19014f82381feb0001', '2c9c486e4fa659ef014fa6dd31ff005c']

  private static hasClass(node: CampusHtmlNode, name: string): boolean {
    return (node.attributes['class'] ?? '').split(/\s+/).includes(name)
  }
  private static findClass(node: CampusHtmlNode, name: string): CampusHtmlNode[] {
    let rows: CampusHtmlNode[] = ReservationParser.hasClass(node, name) ? [node] : []
    for (const child of node.children) rows = rows.concat(ReservationParser.findClass(child, name))
    return rows
  }
  private static descendants(node: CampusHtmlNode, tag: string): CampusHtmlNode[] {
    let rows: CampusHtmlNode[] = node.tag === tag ? [node] : []
    for (const child of node.children) rows = rows.concat(ReservationParser.descendants(child, tag))
    return rows
  }
  private static document(html: string): CampusHtmlNode {
    if (FduAuthPolicy.isLoginDocument(html) || /(?:location(?:\.href)?\s*=|location\.replace\s*\()[\s"']*[^\n;]*login2\.action/i.test(html)) {
      throw new HttpError(-2, 0, AppLanguage.text($r('app.string.reservation_verification_hint')), '')
    }
    if (html.length > 2000000) throw new Error('ReservationDocumentTooLarge')
    return CampusHtml.parse(html)
  }

  static playgrounds(html: string, categoryId: string): Playground[] {
    const containers: CampusHtmlNode[] = ReservationParser.findClass(ReservationParser.document(html), 'order_list')
    if (containers.length === 0) throw new Error(AppLanguage.text($r('app.string.reservation_data_invalid')) + ' (ReservationCatalogStructureError)')
    const result: Playground[] = []
    for (const container of containers) {
      for (const outer of container.direct('table')) {
        for (const row of outer.rows()) {
          for (const cell of row.direct('td')) {
            for (const table of cell.direct('table')) {
              const rows: CampusHtmlNode[] = table.rows()
              if (rows.length === 0) continue
              const link = ReservationParser.descendants(rows[0], 'a')[0]
              const id = /(?:[?&])contentId=([A-Za-z0-9]+)/.exec(link?.attributes['href'] ?? '')?.[1] ?? ''
              const name: string = link?.orderedText() ?? ''
              let campus: string = ''; let category: string = ''
              for (const item of rows) {
                const cells: CampusHtmlNode[] = item.children.filter((node: CampusHtmlNode) => node.tag === 'th' || node.tag === 'td')
                if (cells.length < 2) continue
                if (cells[0].orderedText().includes('校区')) campus = cells[1].orderedText()
                if (cells[0].orderedText().includes('项目')) category = cells[1].orderedText()
              }
              if (id && name && campus && category && !result.some((item: Playground) => item.id === id)) {
                result.push({ id: id, name: name, campus: campus, category: category, categoryId: categoryId })
              }
            }
          }
        }
      }
    }
    if (result.length === 0 && containers.some((node: CampusHtmlNode) => ReservationParser.descendants(node, 'a')
      .some((link: CampusHtmlNode) => (link.attributes['href'] ?? '').includes('contentId=')))) {
      throw new Error(AppLanguage.text($r('app.string.reservation_data_invalid')) + ' (ReservationCatalogIncomplete)')
    }
    return result
  }

  static slots(html: string, playground: Playground, date: string): ReservationSlot[] {
    const root: CampusHtmlNode = ReservationParser.document(html)
    if (html.includes('无可预约场地')) return []
    const container: CampusHtmlNode | undefined = root.findId('con_one_1')
    if (container === undefined) throw new Error(AppLanguage.text($r('app.string.reservation_data_invalid')) + ' (ReservationSlotsStructureError)')
    const result: ReservationSlot[] = []
    let candidates: number = 0
    for (const table of container.direct('table')) {
      for (const row of table.rows()) {
        const cells: CampusHtmlNode[] = row.direct('td')
        const time: CampusHtmlNode | undefined = cells.find((node: CampusHtmlNode) => ReservationParser.hasClass(node, 'site_td1'))
        if (time === undefined) continue
        candidates++
        const times: string[] = time.orderedText().match(/(?:[01]\d|2[0-3]):[0-5]\d/g) ?? []
        const count: CampusHtmlNode | undefined = cells.find((node: CampusHtmlNode) => ReservationParser.hasClass(node, 'site_td4'))
        const numbers: string[] = count?.orderedText().match(/\d+/g) ?? []
        if (times.length !== 2 || numbers.length !== 2) continue
        const reserveId: string = ReservationParser.descendants(row, 'img').map((node: CampusHtmlNode): string =>
          /checkUser\(\s*['"]([A-Za-z0-9]+)['"]\s*,\s*this\s*\)/.exec(node.attributes['onclick'] ?? '')?.[1] ?? '').find((value: string) => value.length > 0) ?? ''
        const name: string = cells.find((node: CampusHtmlNode) => ReservationParser.hasClass(node, 'site_td3'))?.orderedText() ?? playground.name
        result.push({ id: playground.id + '/' + date + '/' + times.join('-') + '/' + reserveId + '/' + String(result.length),
          name: name, begin: times[0], end: times[1], reserved: Number(numbers[0]), total: Number(numbers[1]),
          reserveId: reserveId, categoryId: playground.categoryId, playgroundId: playground.id })
      }
    }
    if (result.length < candidates) throw new Error(AppLanguage.text($r('app.string.reservation_data_invalid')) + ' (ReservationSlotsIncomplete)')
    return result
  }

  static available(slot: ReservationSlot): boolean { return slot.reserveId.length > 0 }
  static bookingUrl(slot: ReservationSlot): string {
    if (![slot.playgroundId, slot.categoryId, slot.reserveId].every((id: string) => /^[A-Za-z0-9]+$/.test(id))) return ''
    return ReservationParser.ORIGIN + '/public/front/loadOrderForm_ordinary.htm?serviceContent.id=' + slot.playgroundId +
      '&serviceCategory.id=' + slot.categoryId + '&resourceIds=' + slot.reserveId + '&codeStr&orderCounts=1'
  }
}
