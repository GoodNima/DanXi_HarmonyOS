import { HttpError } from '../util/HttpUtil'

export interface LibraryReader { barcode: string; name: string; canLoanTotal?: number; currentRequestCount?: number }
interface Catalogue { title?: string; author?: string }
interface LoanLog { itemBarcode?: string; loanDate: string; dueDate: string; renewalCount: number }
interface LibraryItem { barcode?: string; temporaryLibraryName?: string; temporaryLocationName?: string }
interface ItemInfo { item?: LibraryItem; instance?: Catalogue }
interface LoanPolicy { renewalCount?: number }
interface CurrentLoanWire { loanLog: LoanLog; itemInfo?: ItemInfo; circulationLoanPolicy?: LoanPolicy }
interface HistoricLoanWire { catalogueId?: number; itemBarcode: string; loanDate: string; returnDate?: string; dueDate?: string; renewalCount?: number; catalogueInstance?: Catalogue }
interface BookRequestWire { id: number; catalogueId?: number; itemBarcode: string; instance?: Catalogue; status: string; statusCode?: string; pickupLocation: string; pickUpLocationName?: string; expectDate?: string; createTime?: string; allowReplace?: string; queuing?: number }
export class LibraryAccountItem {
  id: string = ''; title: string = ''; author: string = ''; barcode: string = ''; library: string = ''; location: string = ''
  loanDate: string = ''; dueDate: string = ''; returnDate: string = ''; renewals: number = 0; renewalLimit: number = -1
  requestId: number = 0; status: string = ''; pickup: string = ''; expected: string = ''; queue: number = 0
}
interface LibraryWirePage<T> { list: T[]; total: number; pageNo?: number; pageSize?: number }
interface LibraryRawPage<T> {
  list?: T[] | null; records?: T[] | null; total?: number | string | null;
  totalCount?: number | string | null; pageNo?: number | string; pageSize?: number | string; size?: number | string
}
export class LibraryAccountResult { rows: LibraryAccountItem[] = []; hasMore: boolean = false }
export interface LibraryPickup { code: string; name: string; address?: string }
export interface LibraryPickupList { loan: LibraryPickup[]; available: LibraryPickup[] }
export interface LibraryRequestPolicy { requestDateRange: number; matchLoanPolicy: boolean }
export interface LibraryRequestOptions { policy: LibraryRequestPolicy; locations: LibraryPickup[] }
interface LibraryEnvelope<T> { code: number; data?: T; msg?: string; message?: string }
export class LibraryDataMissingError extends Error {
  constructor(detail: string) {
    super('图书馆服务返回的数据缺失，请稍后重新加载。\n\n详细信息 / Details\nLibraryDataMissingError: Library account data missing; ' + detail)
    this.name = 'LibraryDataMissingError'
  }
}
export class LibraryAccountParser {
  private static count(value: number | string | null | undefined, fallback: number): number {
    if (value === null || value === undefined) return fallback
    if (typeof value === 'string' && !/^\d+$/.test(value.trim())) throw new Error('Invalid library pagination number')
    const count: number = Number(value)
    if (!Number.isSafeInteger(count) || count < 0) throw new Error('Invalid library pagination number')
    return count
  }
  private static page<T>(body: string, page: number, requestedSize: number = 20): LibraryWirePage<T> {
    const raw = LibraryAccountParser.data<LibraryRawPage<T>>(body)
    const list: T[] | null | undefined = raw.list !== undefined ? raw.list : raw.records
    const total: number = LibraryAccountParser.count(raw.total ?? raw.totalCount, -1)
    // A zero-total page may have list:null. Missing or malformed nonempty data
    // remains a diagnostic error rather than silently becoming an empty list.
    if (!Array.isArray(list) && !(list === null && total === 0)) {
      if ((list === null || list === undefined) && total === -1) {
        throw new LibraryDataMissingError('list=' + (list === null ? 'null' : 'missing') + '; total=' +
          (raw.total === null ? 'null' : raw.totalCount === null ? 'null' : 'missing'))
      }
      throw new Error('Invalid library account page; fields=' + Object.keys(raw).join(',') + '; listType=' + typeof list + '; totalType=' + typeof raw.total)
    }
    const rows: T[] = list ?? []
    const size: number = LibraryAccountParser.count(raw.pageSize ?? raw.size, requestedSize)
    if (size <= 0 || size > 1000 || (total >= 0 && total < rows.length)) throw new Error('Invalid library pagination bounds')
    return { list: rows, total: total >= 0 ? total : (page - 1) * size + rows.length + (rows.length === size ? 1 : 0), pageSize: size }
  }
  static data<T>(body: string): T {
    if (body.length > 4 * 1024 * 1024) throw new Error('Library account response is too large')
    const wire = JSON.parse(body) as LibraryEnvelope<T>
    if (wire.code === 401 || wire.code === 403) throw new HttpError(-2, wire.code, '图书馆读者会话已失效，请点击继续验证。', '')
    if (wire.code !== 200 || wire.data === undefined || wire.data === null) throw new Error('Library ' + wire.code + ': ' + (wire.message || wire.msg || '图书馆请求失败'))
    return wire.data
  }
  static status(body: string): void {
    const wire = JSON.parse(body) as LibraryEnvelope<Object>
    if (wire.code === 401 || wire.code === 403) throw new HttpError(-2, wire.code, '图书馆读者会话已失效，请点击继续验证。', '')
    if (wire.code !== 200) throw new Error('Library ' + wire.code + ': ' + (wire.message || wire.msg || '图书馆操作失败'))
  }
  static current(body: string, page: number): LibraryAccountResult {
    const wire = LibraryAccountParser.page<CurrentLoanWire>(body, page), result = new LibraryAccountResult()
    result.rows = wire.list.map((row: CurrentLoanWire): LibraryAccountItem => {
      if (!row.loanLog) throw new Error('Library loan log is missing')
      const value = new LibraryAccountItem(); value.barcode = row.itemInfo?.item?.barcode || row.loanLog.itemBarcode || ''
      if (!value.barcode) throw new Error('Library loan barcode is missing')
      value.id = value.barcode; value.title = row.itemInfo?.instance?.title || value.barcode; value.author = row.itemInfo?.instance?.author || ''
      value.library = row.itemInfo?.item?.temporaryLibraryName || ''; value.location = row.itemInfo?.item?.temporaryLocationName || ''
      value.loanDate = row.loanLog.loanDate; value.dueDate = row.loanLog.dueDate; value.renewals = row.loanLog.renewalCount; value.renewalLimit = row.circulationLoanPolicy?.renewalCount ?? -1; return value
    }); result.hasMore = result.rows.length > 0 && page * (wire.pageSize || 20) < wire.total; return result
  }
  static history(body: string, page: number, requestedSize: number = 10): LibraryAccountResult {
    const wire = LibraryAccountParser.page<HistoricLoanWire>(body, page, requestedSize), result = new LibraryAccountResult()
    result.rows = wire.list.map((row: HistoricLoanWire): LibraryAccountItem => {
      if (!row.itemBarcode || !row.loanDate) throw new Error('Library historic loan identity is missing')
      const value = new LibraryAccountItem(); value.barcode = row.itemBarcode; value.id = row.itemBarcode + '-' + row.loanDate
      value.title = row.catalogueInstance?.title || row.itemBarcode; value.author = row.catalogueInstance?.author || ''
      value.loanDate = row.loanDate; value.dueDate = row.dueDate || ''; value.returnDate = row.returnDate || ''; value.renewals = row.renewalCount ?? 0; return value
    }); result.hasMore = result.rows.length > 0 && page * (wire.pageSize || requestedSize) < wire.total; return result
  }
  static requests(body: string, page: number): LibraryAccountResult {
    const wire = LibraryAccountParser.page<BookRequestWire>(body, page), result = new LibraryAccountResult()
    result.rows = wire.list.map((row: BookRequestWire): LibraryAccountItem => {
      const value = new LibraryAccountItem(); value.id = String(row.id); value.requestId = row.id; value.barcode = row.itemBarcode
      value.title = row.instance?.title || row.itemBarcode; value.author = row.instance?.author || ''; value.status = row.status
      value.pickup = row.pickUpLocationName || row.pickupLocation; value.expected = row.expectDate || ''; value.queue = row.queuing ?? 0; return value
    }); result.hasMore = result.rows.length > 0 && page * (wire.pageSize || 20) < wire.total; return result
  }
  static overdue(value: string, now: Date = new Date()): boolean { return /^\d{4}-\d{2}-\d{2}/.test(value) && new Date(value.slice(0, 10) + 'T23:59:59').getTime() < now.getTime() }
}
