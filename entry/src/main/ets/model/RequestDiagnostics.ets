class RequestDiagnostic {
  at: number = 0
  method: string = ''
  endpoint: string = ''
  status: number = 0
  code: number = 0
  elapsedMs: number = 0
  phase: string = ''
  details: string = ''
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
    code: number, elapsedMs: number, phase: string, details: string = ''): string {
    if (epoch !== currentEpoch) return ''
    if (RequestDiagnostics.epoch !== epoch) { RequestDiagnostics.epoch = epoch; RequestDiagnostics.rows = [] }
    const row = new RequestDiagnostic()
    row.at = Date.now(); row.method = /^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)$/i.test(method) ? method : 'HTTP'
    row.endpoint = RequestDiagnostics.endpoint(url); row.status = status; row.code = code
    row.elapsedMs = Number.isFinite(elapsedMs) ? Math.max(0, Math.round(elapsedMs)) : 0
    row.phase = /^[a-z-]{1,40}$/.test(phase) ? phase : 'transport'
    row.details = RequestDiagnostics.safeDetails(details)
    RequestDiagnostics.rows.push(row)
    if (RequestDiagnostics.rows.length > 64) RequestDiagnostics.rows.splice(0, RequestDiagnostics.rows.length - 64)
    // The failure owns this immutable string even after recent global logs expire.
    return RequestDiagnostics.format(row)
  }

  private static safeDetails(value: string): string {
    const keys: string[] = ['dnsMs', 'tcpMs', 'tlsMs', 'sendMs', 'sendElapsedMs', 'firstReceiveMs', 'firstByteMs',
      'headerMs', 'headersMs', 'bodyMs', 'totalMs', 'receiveMs', 'connectMs', 'cookieMs', 'elapsedMs', 'budgetMs',
      'totalBudgetMs', 'connectBudgetMs', 'readBudgetMs', 'receiveBudgetMs', 'sentBytes', 'receivedBytes', 'uploadBytes', 'expectedBytes', 'downloadBytes',
      'headersReceived', 'sendCompleted', 'bodyReceived', 'fresh', 'reused', 'proxied', 'usingProxy', 'timingAvailable']
    const parts: string[] = []
    for (const item of value.substring(0, 4096).split(/[;\n]/)) {
      const proxy = /^proxyPolicy=(system|disabled|custom)$/.exec(item.trim())
      if (proxy !== null) {
        if (!parts.some((part: string): boolean => part.startsWith('proxyPolicy='))) parts.push('proxyPolicy=' + proxy[1])
        continue
      }
      const pair = /^([A-Za-z][A-Za-z0-9]{0,31})\s*=\s*(unknown|-?\d+(?:\.\d+)?|true|false)$/.exec(item.trim())
      if (pair !== null) {
        const key: string = pair[1]
        if (keys.includes(key) && !parts.some((part: string): boolean => part.startsWith(key + '='))) parts.push(key + '=' + pair[2])
      } else {
        const named = /^(route|timeoutSource)\s*=\s*([a-z-]{1,40})$/.exec(item.trim())
        if (named !== null && ['direct', 'webvpn', 'native', 'receive-deadline', 'overall-deadline', 'unknown'].includes(named[2])) {
          const key: string = named[1]
          if (!parts.some((part: string): boolean => part.startsWith(key + '='))) parts.push(key + '=' + named[2])
        }
      }
    }
    return parts.join('; ').substring(0, 1600)
  }

  private static format(row: RequestDiagnostic): string {
    return new Date(row.at).toISOString() + ' ' + row.method + ' ' + row.endpoint +
      '\nstatus=' + row.status + '; code=' + row.code + '; elapsedMs=' + row.elapsedMs + '; phase=' + row.phase +
      (row.details ? '\n' + row.details : '')
  }

  static report(epoch: number): string {
    if (RequestDiagnostics.epoch !== epoch) return ''
    return RequestDiagnostics.rows.filter((row: RequestDiagnostic): boolean => Date.now() - row.at < 120000).slice(-24)
      .map((row: RequestDiagnostic): string => RequestDiagnostics.format(row)).join('\n\n')
  }
}
