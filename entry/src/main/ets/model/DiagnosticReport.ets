import { CampusCookies } from '../common/CampusCookies'
import { Constant } from '../common/Constant'
import { ErrorDiagnostics } from './ErrorDiagnostics'
import { RequestDiagnostics } from './RequestDiagnostics'
import { ForumImageDiagnostics } from './ForumImageDiagnostics'

export class DiagnosticReport {
  id: string = ''
  epoch: number = 0
  createdAt: number = 0
  summary: string = ''
  error: string = ''
  logs: string = ''
  source: string = ''

  text(): string {
    return Constant.APP_DIAGNOSTIC_HEADER + '\n' +
      new Date(this.createdAt).toISOString() + (this.source ? '\nsource=' + this.source : '') +
      '\n\n' + this.summary + '\n\nError\n' + this.error + (this.logs ? '\n\nLogs\n' + this.logs : '')
  }
}

/** Only a short-lived identifier enters the sheet. Error snapshots stay local and account-scoped. */
export class DiagnosticReports {
  private static sequence: number = 0
  private static epoch: number = -1
  private static reports: DiagnosticReport[] = []

  static capture(message: string, logs: string = '', source: string = '', summary: string = ''): DiagnosticReport {
    const epoch = CampusCookies.generation()
    if (epoch !== DiagnosticReports.epoch) { DiagnosticReports.epoch = epoch; DiagnosticReports.reports = [] }
    const report = new DiagnosticReport()
    report.id = String(++DiagnosticReports.sequence); report.epoch = epoch; report.createdAt = Date.now()
    report.summary = ErrorDiagnostics.brief(message, summary)
    report.error = ErrorDiagnostics.technical(message)
    report.source = /^[a-zA-Z/._-]{0,100}$/.test(source) ? source : ''
    const associated: string = ErrorDiagnostics.associated(message)
    if (associated) {
      // Keep the failed operation's own snapshot, not whichever requests ran while
      // the user was reading the error or opening this sheet minutes later.
      report.logs = ErrorDiagnostics.safe((logs ? logs + '\n\n' : '') + 'Associated request\n' + associated, 16000)
    } else {
      const requests: string = RequestDiagnostics.report(epoch)
      const images: string = ForumImageDiagnostics.report(epoch)
      const transport: string = logs + (images ? (logs ? '\n\n' : '') + 'Image transfers\n' + images : '')
      report.logs = ErrorDiagnostics.safe((transport + (requests ? (transport ? '\n\n' : '') + 'Recent requests\n' + requests : '')).trim(), 16000)
    }
    DiagnosticReports.reports.push(report)
    if (DiagnosticReports.reports.length > 8) DiagnosticReports.reports.shift()
    return report
  }

  static get(id: string): DiagnosticReport | null {
    const epoch = CampusCookies.generation()
    if (epoch !== DiagnosticReports.epoch) { DiagnosticReports.reports = []; DiagnosticReports.epoch = epoch; return null }
    return DiagnosticReports.reports.find((report: DiagnosticReport): boolean => report.id === id &&
      report.epoch === epoch && Date.now() - report.createdAt < 1200000) ?? null
  }
}
