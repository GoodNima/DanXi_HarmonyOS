import { CampusHtml } from './CampusHtml'

export class LibraryBook {
  id: string = ''
  title: string = ''
  authors: string[] = []
  publisher: string = ''
  year: string = ''
  isbn: string = ''
  summary: string = ''
}
export class LibraryHolding {
  id: string = ''
  callNumber: string = ''
  library: string = ''
  location: string = ''
  status: string = ''
  volume: string = ''
  barcode: string = ''; libraryCode: string = ''; locationCode: string = ''; canRequest: boolean | undefined = undefined
}
interface BookWire {
  docId?: string; resource_ztm?: string; resource_zrz_arr?: string[]; resource_cbz?: string;
  publication_year_int?: number; resource_cbrq?: string; resource_isbn_arr?: string[]; resource_zydfz?: string
}
interface HoldingWire { id?: string; callNo?: string; temporaryLibraryName?: string; temporaryLocationName?: string; itemStatusName?: string; volumeInfo?: string; barcode?: string; temporaryLibraryCode?: string; temporaryLocationCode?: string; requestFlag?: boolean }
interface BookData { list?: BookWire[]; total?: number; totalCount?: number }
interface HoldingsData { list?: HoldingWire[]; total?: number; totalCount?: number }
interface BookEnvelope { success?: boolean; code?: number; msg?: string; data?: BookData }
interface BookDetailEnvelope { success?: boolean; code?: number; msg?: string; data?: BookWire[] }
interface HoldingsEnvelope { code?: number; msg?: string; data?: HoldingsData }
export class LibraryBookPage { rows: LibraryBook[] = []; hasMore: boolean = false }
export class LibraryHoldingPage { rows: LibraryHolding[] = []; hasMore: boolean = false }
export interface BookSearchCondition { field: string; matchType: string; value: string; operator: string; noTransaction: boolean }
export interface BookSearchPayload {
  resourceType: number; pageSize: number; pageNum: number; searchConditions: BookSearchCondition[];
  orderByField: string; orderByType: string; aiQuery: boolean; aiMinimumShouldMatch: string; publicationYearFrom: string; publicationYearTo: string
}
export class LibraryBookParser {
  static readonly ORIGIN: string = 'https://fdulspgw.fudan.edu.cn'
  static readonly PAGE_SIZE: number = 20
  static payload(query: string, page: number): BookSearchPayload {
    if (!query.trim() || query.length > 200 || !Number.isInteger(page) || page < 1) throw new Error('Invalid library book search')
    return { resourceType: 1, pageSize: LibraryBookParser.PAGE_SIZE, pageNum: page,
      searchConditions: [{ field: 'resource_ztm', matchType: 'contains', value: query.trim(), operator: 'AND', noTransaction: false }],
      orderByField: 'similarity', orderByType: 'desc', aiQuery: false, aiMinimumShouldMatch: '70%', publicationYearFrom: '', publicationYearTo: '' }
  }
  static books(body: string, page: number): LibraryBookPage {
    LibraryBookParser.validateSize(body)
    const wire = JSON.parse(body) as BookEnvelope
    if (!wire || !wire.success || wire.code !== 200 || !wire.data) throw new Error('Library book search failed: ' + (wire?.msg ?? 'Invalid response'))
    const result = new LibraryBookPage()
    if (wire.data.list !== undefined && wire.data.list !== null && !Array.isArray(wire.data.list)) throw new Error('Invalid library book list')
    result.rows = (wire.data.list ?? []).map((row: BookWire): LibraryBook => LibraryBookParser.book(row))
    result.hasMore = LibraryBookParser.hasMore(result.rows.length, page, wire.data.total ?? wire.data.totalCount)
    return result
  }
  static detail(body: string): LibraryBook {
    LibraryBookParser.validateSize(body)
    const wire = JSON.parse(body) as BookDetailEnvelope
    if (!wire || !wire.success || wire.code !== 200 || !Array.isArray(wire.data) || wire.data.length === 0) throw new Error('Library book detail failed: ' + (wire?.msg ?? 'Book not found'))
    return LibraryBookParser.book(wire.data[0])
  }
  static holdings(body: string, page: number): LibraryHoldingPage {
    LibraryBookParser.validateSize(body)
    const wire = JSON.parse(body) as HoldingsEnvelope
    if (!wire || wire.code !== 200 || !wire.data) throw new Error('Library holdings failed: ' + (wire?.msg ?? 'Invalid response'))
    if (wire.data.list !== undefined && wire.data.list !== null && !Array.isArray(wire.data.list)) throw new Error('Invalid library holdings list')
    const result = new LibraryHoldingPage()
    result.rows = (wire.data.list ?? []).map((row: HoldingWire): LibraryHolding => {
      if (!row || typeof row.id !== 'string' || !row.id || typeof row.itemStatusName !== 'string') throw new Error('Library holding fields are incomplete')
      const item = new LibraryHolding(); item.id = row.id; item.callNumber = typeof row.callNo === 'string' ? row.callNo : ''
      item.library = typeof row.temporaryLibraryName === 'string' ? row.temporaryLibraryName : ''
      item.location = typeof row.temporaryLocationName === 'string' ? row.temporaryLocationName : ''; item.status = row.itemStatusName
      item.volume = typeof row.volumeInfo === 'string' ? row.volumeInfo : ''
      item.barcode = row.barcode ?? ''; item.libraryCode = row.temporaryLibraryCode ?? ''; item.locationCode = row.temporaryLocationCode ?? ''; item.canRequest = row.requestFlag; return item
    })
    result.hasMore = LibraryBookParser.hasMore(result.rows.length, page, wire.data.total ?? wire.data.totalCount)
    return result
  }
  private static book(row: BookWire): LibraryBook {
    if (!row || typeof row.docId !== 'string' || !row.docId || typeof row.resource_ztm !== 'string') throw new Error('Library book fields are incomplete')
    const item = new LibraryBook(); item.id = row.docId; item.title = LibraryBookParser.plain(row.resource_ztm)
    if (!item.title) throw new Error('Library book title is empty')
    item.authors = Array.isArray(row.resource_zrz_arr) ? row.resource_zrz_arr.filter((value: string) => typeof value === 'string') : []
    item.publisher = typeof row.resource_cbz === 'string' ? LibraryBookParser.plain(row.resource_cbz) : ''
    item.year = Number.isSafeInteger(row.publication_year_int) ? String(row.publication_year_int) : typeof row.resource_cbrq === 'string' ? row.resource_cbrq : ''
    const isbns: string[] = Array.isArray(row.resource_isbn_arr) ? row.resource_isbn_arr.filter((value: string) => typeof value === 'string') : []
    item.isbn = isbns.find((value: string) => value.replace(/\D/g, '').length === 13) ?? isbns[0] ?? ''
    item.summary = typeof row.resource_zydfz === 'string' ? LibraryBookParser.plain(row.resource_zydfz) : ''; return item
  }
  static plain(text: string): string { return CampusHtml.decode(text.replace(/<[^>]+>/g, '')).trim() }
  private static validateSize(body: string): void { if (body.length > 4 * 1024 * 1024) throw new Error('Library response is too large') }
  private static hasMore(count: number, page: number, total: number | undefined): boolean {
    return count > 0 && (total !== undefined && Number.isSafeInteger(total) && total >= 0 ? page * LibraryBookParser.PAGE_SIZE < total : count === LibraryBookParser.PAGE_SIZE)
  }
}
