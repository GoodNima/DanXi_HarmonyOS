import { RequestDiagnostics } from './RequestDiagnostics'

/** Transport metadata only: no image identifiers, signed queries, headers or bytes. */
export class ForumImageAttempt {
  epoch: number = 0
  at: number = 0
  endpoint: string = ''
  read: number = 0
  attempt: number = 1
  route: string = 'direct'
  fresh: boolean = false
  status: number = -1
  code: number = 0
  phase: string = 'await-response-headers'
  elapsedMs: number = 0
  headerMs: number = -1
  firstByteMs: number = -1
  receivedBytes: number = 0
  expectedBytes: number = -1
  timeoutSource: string = ''
}

export class ForumImageDiagnostics {
  private static epoch: number = -1
  private static rows: ForumImageAttempt[] = []
  private static sequence: number = 0

  static nextRead(): number { return ++ForumImageDiagnostics.sequence }

  static begin(epoch: number, address: string, read: number, attempt: number, fresh: boolean, proxy: boolean): ForumImageAttempt {
    const row = new ForumImageAttempt()
    // Image filenames and directory names can contain private content even
    // without query tokens. Retain only the host and a fixed route shape.
    row.epoch = epoch; row.at = Date.now(); row.read = read
    row.endpoint = RequestDiagnostics.endpoint(address).split('/')[0] + (proxy ? '/https/:host/:image' : '/:image')
    row.attempt = attempt; row.fresh = fresh; row.route = proxy ? 'webvpn' : 'direct'
    return row
  }

  static finish(row: ForumImageAttempt, currentEpoch: number): void {
    if (row.epoch !== currentEpoch) return
    if (ForumImageDiagnostics.epoch !== currentEpoch) {
      ForumImageDiagnostics.epoch = currentEpoch; ForumImageDiagnostics.rows = []
    }
    row.elapsedMs = Math.max(0, Date.now() - row.at)
    ForumImageDiagnostics.rows.push(row)
    if (ForumImageDiagnostics.rows.length > 16) ForumImageDiagnostics.rows.shift()
    RequestDiagnostics.record(row.epoch, currentEpoch, 'GET', 'https://' + row.endpoint,
      row.status, row.code, row.elapsedMs, row.phase)
  }

  static report(epoch: number): string {
    if (ForumImageDiagnostics.epoch !== epoch) return ''
    return ForumImageDiagnostics.rows.filter((row: ForumImageAttempt): boolean => Date.now() - row.at - row.elapsedMs < 120000)
      .slice(-8).map((row: ForumImageAttempt): string => new Date(row.at).toISOString() + ' GET ' + row.endpoint +
        '\nread=' + row.read + '; attempt=' + row.attempt + '; route=' + row.route + '; fresh=' + String(row.fresh) +
        '; status=' + row.status + '; code=' + row.code + '; phase=' + row.phase + '; elapsedMs=' + row.elapsedMs +
        '\nheaderMs=' + row.headerMs + '; firstByteMs=' + row.firstByteMs + '; receivedBytes=' + row.receivedBytes +
        '; expectedBytes=' + row.expectedBytes + (row.timeoutSource ? '; timeoutSource=' + row.timeoutSource : '')).join('\n\n')
  }
}
