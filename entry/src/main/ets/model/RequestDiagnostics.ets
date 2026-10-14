class RequestDiagnostic {
  at: number = 0
  method: string = ''
  endpoint: string = ''
  status: number = 0
  code: number = 0
  elapsedMs: number = 0
  phase: string = ''
}

/** Bounded, account-scoped transport metadata. Never retains bodies, headers or query values. */
export class RequestDiagnostics {
  private static epoch: number = -1
  private static rows: RequestDiagnostic[] = []

  static endpoint(url: string): string {
    const match = /^https?:\/\/([a-z0-9.-]+)(?::\d+)?(\/[^?#]*)?/i.exec(url)
    if (match === null) return '[endpoint omitted]'
    const parts: string[] = (match[2] || '/').split('/').map((part: string): string => {
      return /^[a-z][a-z_-]{0,39}(?:\.[a-z]{1,5})?$/i.test(part) ? part : part ? ':id' : ''
    })
    return (match[1] + parts.join('/')).substring(0, 180)
  }

  static record(epoch: number, currentEpoch: number, method: string, url: string, status: number,
    code: number, elapsedMs: number, phase: string): void {
    if (epoch !== currentEpoch) return
    if (RequestDiagnostics.epoch !== epoch) { RequestDiagnostics.epoch = epoch; RequestDiagnostics.rows = [] }
    const row = new RequestDiagnostic()
    row.at = Date.now(); row.method = /^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)$/i.test(method) ? method : 'HTTP'
    row.endpoint = RequestDiagnostics.endpoint(url); row.status = status; row.code = code
    row.elapsedMs = Number.isFinite(elapsedMs) ? Math.max(0, Math.round(elapsedMs)) : 0
    row.phase = /^[a-z-]{1,40}$/.test(phase) ? phase : 'transport'
    RequestDiagnostics.rows.push(row)
    if (RequestDiagnostics.rows.length > 64) RequestDiagnostics.rows.splice(0, RequestDiagnostics.rows.length - 64)
  }

  static report(epoch: number): string {
    if (RequestDiagnostics.epoch !== epoch) return ''
    return RequestDiagnostics.rows.filter((row: RequestDiagnostic): boolean => Date.now() - row.at < 120000).slice(-24)
      .map((row: RequestDiagnostic): string => new Date(row.at).toISOString() + ' ' + row.method + ' ' + row.endpoint +
        '\nstatus=' + row.status + '; code=' + row.code + '; elapsedMs=' + row.elapsedMs + '; phase=' + row.phase).join('\n\n')
  }
}
