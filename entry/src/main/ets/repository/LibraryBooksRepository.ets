import { LibraryBook, LibraryBookPage, LibraryHoldingPage, LibraryBookParser } from '../model/LibraryBooks'
import { HttpUtil } from '../util/HttpUtil'
import { PreferencesUtil } from '../util/PreferencesUtil'

interface BookPageCache { data: LibraryBookPage; at: number }
interface BookDetailCache { data: LibraryBook; at: number }
interface HoldingsCache { data: LibraryHoldingPage; at: number }
export interface LibraryBooksSource {
  search(query: string, page: number, force: boolean): Promise<LibraryBookPage>
  detail(id: string, force: boolean): Promise<LibraryBook>
  holdings(id: string, page: number, force: boolean): Promise<LibraryHoldingPage>
}
/** Public iOS catalogue endpoints require no campus authentication. Different
 * queries cannot overwrite each other, and repeated reads share one flight. */
export class LibraryBooksRepository {
  private static searches: Map<string, BookPageCache> = new Map()
  private static details: Map<string, BookDetailCache> = new Map()
  private static stocks: Map<string, HoldingsCache> = new Map()
  private static searchFlights: Map<string, Promise<LibraryBookPage>> = new Map()
  private static detailFlights: Map<string, Promise<LibraryBook>> = new Map()
  private static stockFlights: Map<string, Promise<LibraryHoldingPage>> = new Map()
  static readonly PIN_KEY: string = 'library_pinned_books'
  static readonly PIN_REVISION: string = 'library_pinned_books_revision'
  private static pinWrites: Promise<void> = Promise.resolve()
  static async search(query: string, page: number, force: boolean = false): Promise<LibraryBookPage> {
    const payload = LibraryBookParser.payload(query, page), key: string = query.trim() + '/' + page
    const cached = LibraryBooksRepository.searches.get(key)
    if (!force && cached !== undefined && Date.now() - cached.at < 300000) return cached.data
    const pending = LibraryBooksRepository.searchFlights.get(key); if (pending !== undefined) return pending
    const task = HttpUtil.getInstance().post(LibraryBookParser.ORIGIN + '/urdh/open-api/opac/search/advanced', JSON.stringify(payload),
      { 'Accept': 'application/json', 'Content-Type': 'application/json', 'User-Agent': HttpUtil.BROWSER_UA, 'Authorization': '' })
      .then((response): LibraryBookPage => { const data = LibraryBookParser.books(response.data, page); LibraryBooksRepository.searches.set(key, { data: data, at: Date.now() });
        while (LibraryBooksRepository.searches.size > 32) { const first: string | undefined = LibraryBooksRepository.searches.keys().next().value; if (first !== undefined) LibraryBooksRepository.searches.delete(first) } return data
      }).finally(() => { if (LibraryBooksRepository.searchFlights.get(key) === task) LibraryBooksRepository.searchFlights.delete(key) })
    LibraryBooksRepository.searchFlights.set(key, task); return task
  }
  static async detail(id: string, force: boolean = false): Promise<LibraryBook> {
    LibraryBooksRepository.checkId(id)
    const cached = LibraryBooksRepository.details.get(id)
    if (!force && cached !== undefined && Date.now() - cached.at < 600000) return cached.data
    const pending = LibraryBooksRepository.detailFlights.get(id); if (pending !== undefined) return pending
    const task = HttpUtil.getInstance().get(LibraryBookParser.ORIGIN + '/urdh/open-api/opac/search/smjlh/' + encodeURIComponent(id), undefined,
      { 'Accept': 'application/json', 'User-Agent': HttpUtil.BROWSER_UA, 'Authorization': '' }, 12000).then((response): LibraryBook => {
        const data = LibraryBookParser.detail(response.data); if (data.id !== id) throw new Error('Library book detail ID mismatch')
        LibraryBooksRepository.details.set(id, { data: data, at: Date.now() });
        while (LibraryBooksRepository.details.size > 32) { const first: string | undefined = LibraryBooksRepository.details.keys().next().value; if (first !== undefined) LibraryBooksRepository.details.delete(first) } return data
      }).finally(() => { if (LibraryBooksRepository.detailFlights.get(id) === task) LibraryBooksRepository.detailFlights.delete(id) })
    LibraryBooksRepository.detailFlights.set(id, task); return task
  }
  static async holdings(id: string, page: number, force: boolean = false): Promise<LibraryHoldingPage> {
    LibraryBooksRepository.checkId(id)
    if (!Number.isInteger(page) || page < 1) throw new Error('Invalid library holdings page')
    const key: string = id + '/' + page, cached = LibraryBooksRepository.stocks.get(key)
    if (!force && cached !== undefined && Date.now() - cached.at < 60000) return cached.data
    const pending = LibraryBooksRepository.stockFlights.get(key); if (pending !== undefined) return pending
    const task = HttpUtil.getInstance().get(LibraryBookParser.ORIGIN + '/alsp/open-api/opac/v2/holdings',
      { 'catalogueId': id, 'loanTypeCode': '', 'pageSize': '20', 'pageNo': String(page), 'display': 'true' },
      { 'Accept': 'application/json', 'User-Agent': HttpUtil.BROWSER_UA, 'Authorization': '' }, 12000).then((response): LibraryHoldingPage => {
        const data = LibraryBookParser.holdings(response.data, page); LibraryBooksRepository.stocks.set(key, { data: data, at: Date.now() })
        while (LibraryBooksRepository.stocks.size > 32) { const first: string | undefined = LibraryBooksRepository.stocks.keys().next().value; if (first !== undefined) LibraryBooksRepository.stocks.delete(first) } return data
      }).finally(() => { if (LibraryBooksRepository.stockFlights.get(key) === task) LibraryBooksRepository.stockFlights.delete(key) })
    LibraryBooksRepository.stockFlights.set(key, task); return task
  }
  private static checkId(id: string): void { if (!id.trim() || id.length > 128) throw new Error('Invalid library book ID') }
  static async pinned(): Promise<LibraryBook[]> {
    try { const parsed = JSON.parse(await PreferencesUtil.getInstance().getString(LibraryBooksRepository.PIN_KEY, '[]')) as LibraryBook[]
      return Array.isArray(parsed) ? parsed.filter((row: LibraryBook) => row !== null && typeof row.id === 'string' && row.id.length > 0 && typeof row.title === 'string').slice(0, 50)
        .map((row: LibraryBook): LibraryBook => {
          const book = new LibraryBook(); book.id = row.id; book.title = row.title
          book.authors = Array.isArray(row.authors) ? row.authors.filter((value: string) => typeof value === 'string') : []
          book.publisher = typeof row.publisher === 'string' ? row.publisher : ''; book.year = typeof row.year === 'string' ? row.year : ''
          book.isbn = typeof row.isbn === 'string' ? row.isbn : ''; book.summary = typeof row.summary === 'string' ? row.summary : ''; return book
        }) : []
    } catch (e) { return [] }
  }
  static togglePin(book: LibraryBook): Promise<void> {
    const task = LibraryBooksRepository.pinWrites.catch(() => {}).then(async (): Promise<void> => {
      const pinned = await LibraryBooksRepository.pinned(), existing = pinned.some((row: LibraryBook) => row.id === book.id)
      const next: LibraryBook[] = existing ? pinned.filter((row: LibraryBook) => row.id !== book.id) : [book].concat(pinned).slice(0, 50)
      await PreferencesUtil.getInstance().putString(LibraryBooksRepository.PIN_KEY, JSON.stringify(next))
      AppStorage.setOrCreate<number>(LibraryBooksRepository.PIN_REVISION, (AppStorage.get<number>(LibraryBooksRepository.PIN_REVISION) ?? 0) + 1)
    }); LibraryBooksRepository.pinWrites = task; return task
  }
}
export class DefaultLibraryBooksSource implements LibraryBooksSource {
  search(query: string, page: number, force: boolean): Promise<LibraryBookPage> { return LibraryBooksRepository.search(query, page, force) }
  detail(id: string, force: boolean): Promise<LibraryBook> { return LibraryBooksRepository.detail(id, force) }
  holdings(id: string, page: number, force: boolean): Promise<LibraryHoldingPage> { return LibraryBooksRepository.holdings(id, page, force) }
}
