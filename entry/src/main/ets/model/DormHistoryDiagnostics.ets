import { Constant } from '../common/Constant'

export interface DormHistoryQuery { id: number; attempt: number; stage?: string }

/** Transport metadata only: never retain URLs, cookies, headers or usage rows. */
export class DormHistoryTransfer {
  query: number = 0
  attempt: number = 0
  stage: string = 'query'
  startedAt: number = 0
  elapsedMs: number = 0
  budgetMs: number = 0
  fresh: boolean = false
  status: number = 0
  code: number = 0
  sentBytes: number = 0
  uploadBytes: number = 0
  sendElapsedMs: number = 0
  headersReceived: boolean = false
  receiveBudgetMs: number = 0
  timeoutSource: string = ''
  peersAtStart: number = 0
  phase: string = 'connect-or-send'
  timingKnown: boolean = false
  dnsMs: number = 0
  tcpMs: number = 0
  tlsMs: number = 0
  firstReceiveMs: number = 0
  connectionKnown: boolean = false
  reused: boolean = false
  proxied: boolean = false
}

/** A bounded, in-memory comparison survives a successful manual reload, but
 * cannot cross an account/logout epoch. Opening it never accesses the network. */
export class DormHistoryDiagnostics {
  private static epoch: number = -1
  private static sequence: number = 0
  private static transfers: DormHistoryTransfer[] = []

  private static reset(epoch: number): void {
    if (epoch === DormHistoryDiagnostics.epoch) return
    DormHistoryDiagnostics.epoch = epoch
    DormHistoryDiagnostics.sequence = 0
    DormHistoryDiagnostics.transfers = []
  }
  static begin(epoch: number): number {
    DormHistoryDiagnostics.reset(epoch)
    return ++DormHistoryDiagnostics.sequence
  }
  static record(epoch: number, currentEpoch: number, transfer: DormHistoryTransfer): void {
    DormHistoryDiagnostics.reset(currentEpoch)
    if (epoch !== currentEpoch) return
    DormHistoryDiagnostics.transfers.push(transfer)
    if (DormHistoryDiagnostics.transfers.length > 6) DormHistoryDiagnostics.transfers.shift()
  }
  static hasEntries(epoch: number): boolean {
    DormHistoryDiagnostics.reset(epoch)
    return DormHistoryDiagnostics.transfers.length > 0
  }
  static hasFailure(epoch: number): boolean {
    DormHistoryDiagnostics.reset(epoch)
    return DormHistoryDiagnostics.transfers.some((row: DormHistoryTransfer): boolean =>
      row.status >= 400 || (row.code !== 0 && row.phase !== 'redirect'))
  }
  private static number(value: number): string {
    return Number.isFinite(value) ? String(Math.round(value)) : 'unavailable'
  }
  static report(epoch: number): string {
    DormHistoryDiagnostics.reset(epoch)
    if (DormHistoryDiagnostics.transfers.length === 0) return ''
    return Constant.APP_DIAGNOSTIC_HEADER + '\n\n' +
      DormHistoryDiagnostics.transfers.map((row: DormHistoryTransfer): string => {
      const completed: boolean = row.uploadBytes > 0 && row.sentBytes >= row.uploadBytes
      const phase: string = ['connect-or-send', 'upload-incomplete', 'await-response-headers', 'response-body',
        'complete', 'redirect', 'http-error', 'transport-error'].includes(row.phase) ? row.phase : 'unavailable'
      const lines: string[] = [
        'query=' + DormHistoryDiagnostics.number(row.query) + '; attempt=' + DormHistoryDiagnostics.number(row.attempt) +
          '; stage=' + (row.stage === 'portal-session' ? 'portal-session' : 'query') + '; at=' + new Date(row.startedAt).toISOString(),
        'status=' + DormHistoryDiagnostics.number(row.status) + '; code=' + DormHistoryDiagnostics.number(row.code) + '; phase=' + phase,
        'elapsedMs=' + DormHistoryDiagnostics.number(row.elapsedMs) + '; budgetMs=' + DormHistoryDiagnostics.number(row.budgetMs) +
          '; fresh=' + String(row.fresh) + '; peersAtStart=' + DormHistoryDiagnostics.number(row.peersAtStart),
        'sentBytes=' + DormHistoryDiagnostics.number(row.sentBytes) + '; uploadBytes=' + DormHistoryDiagnostics.number(row.uploadBytes) +
          '; sendCompleted=' + String(completed) + '; sendElapsedMs=' + DormHistoryDiagnostics.number(row.sendElapsedMs) +
          '; headersReceived=' + String(row.headersReceived)
      ]
      if (row.receiveBudgetMs > 0) lines.push('receiveBudgetMs=' + DormHistoryDiagnostics.number(row.receiveBudgetMs))
      if (row.timeoutSource) lines.push('timeoutSource=' + (row.timeoutSource === 'receive-deadline' ? 'receive-deadline' : 'native'))
      if (row.timingKnown) lines.push('dnsMs=' + DormHistoryDiagnostics.number(row.dnsMs) + '; tcpMs=' + DormHistoryDiagnostics.number(row.tcpMs) +
        '; tlsMs=' + DormHistoryDiagnostics.number(row.tlsMs) + '; firstReceiveMs=' + DormHistoryDiagnostics.number(row.firstReceiveMs))
      if (row.connectionKnown) lines.push('reused=' + String(row.reused) + '; proxied=' + String(row.proxied))
      return lines.join('\n')
    }).join('\n\n')
  }
}
