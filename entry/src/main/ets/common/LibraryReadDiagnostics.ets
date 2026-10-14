interface LibraryDiagnosticPage { list?: Object | null; records?: Object | null; total?: number | string | null; totalCount?: number | string | null; pageSize?: number | string }
interface LibraryDiagnosticEnvelope { code?: number; data?: LibraryDiagnosticPage | null }

/** Response structure only. Never retain credentials, barcodes or book text. */
export class LibraryReadDiagnostics {
  private static owner: string = ''
  private static lines: string[] = []
  private static type(value: Object | null | undefined): string {
    if (value === null) return 'null'
    if (value === undefined) return 'missing'
    return Array.isArray(value) ? 'array(' + value.length + ')' : typeof value
  }
  static record(owner: string, kind: string, history: boolean, page: number, size: number, body: string): void {
    if (owner !== LibraryReadDiagnostics.owner) { LibraryReadDiagnostics.lines = []; LibraryReadDiagnostics.owner = owner }
    let shape: string = 'body=invalid-json'
    try {
      const wire = JSON.parse(body) as LibraryDiagnosticEnvelope
      const data = wire.data
      shape = 'code=' + (Number.isFinite(wire.code) ? String(wire.code) : 'missing')
      if (data === undefined || data === null) shape += '; data=' + LibraryReadDiagnostics.type(data)
      else {
        const list = data.list !== undefined ? data.list : data.records
        const total = data.total !== undefined ? data.total : data.totalCount
        shape += '; fields=' + Object.keys(data).filter((key: string): boolean => /^[a-zA-Z][a-zA-Z0-9_]{0,40}$/.test(key)).slice(0, 12).join(',') +
          '; list=' + LibraryReadDiagnostics.type(list) + '; total=' + LibraryReadDiagnostics.type(total)
        if (typeof total === 'number' && Number.isSafeInteger(total) && total >= 0) shape += '(' + total + ')'
      }
    } catch (error) { /* Keep a structural diagnostic without the response. */ }
    LibraryReadDiagnostics.lines.push(new Date().toISOString() + ' kind=' + kind + '; history=' + history + '; page=' + page + '; pageSize=' + size + '; ' + shape)
    if (LibraryReadDiagnostics.lines.length > 24) LibraryReadDiagnostics.lines.shift()
  }
  static report(owner: string): string { return owner === LibraryReadDiagnostics.owner ? LibraryReadDiagnostics.lines.join('\n') : '' }
}
