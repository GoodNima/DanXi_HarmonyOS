interface DiagnosticFailure { name?: string; message?: string; statusCode?: number; code?: number }

/** Safe diagnostic text: never display response bodies, cookies or tokens. */
export class ErrorDiagnostics {
  static detail(error: Object): string {
    if (error === null || error === undefined) return 'Error: No error information provided'
    const failure = error as DiagnosticFailure
    const name: string = typeof failure.name === 'string' && failure.name.length > 0 ? failure.name : 'Error'
    const code: number = failure.code ?? 0
    const status: number | undefined = failure.statusCode
    let reason: string = typeof failure.message === 'string' ? failure.message : String(error)
    if (code === 2300028 && !reason.includes('Operation timeout')) reason = 'Operation timeout · ' + reason
    else if (code === 2300006 && !reason.includes('Failed to resolve the host name')) reason = 'Failed to resolve the host name · ' + reason
    else if (code === 401 && status === -1 && !reason.includes('Parameter error')) reason = 'Parameter error · ' + reason
    else if (status !== undefined && status >= 400) reason = 'HTTP ' + status + ' · ' + reason
    else if (status === -2) reason = 'Authentication required · ' + reason
    return name + (status !== undefined ? ' (status=' + status + ', code=' + code + ')' : code ? ' (code=' + code + ')' : '') +
      ': ' + ErrorDiagnostics.safe(reason, 1200)
  }
  static safe(value: string, limit: number = 4000): string {
    return value.replace(/(https?:\/\/[^\s?#]+)[?#][^\s）)]*/gi, '$1?[redacted]')
      .replace(/\b(?:authorization|set-cookie|cookie)\s*[:=]\s*[^\r\n]+/gi, '[credentials redacted]')
      .replace(/\bBearer\s+[^\s,;]+/gi, 'Bearer [redacted]')
      .replace(/(?:["']?\b(?:access_token|refresh_token|token|password|passwd|ticket|session|skey|studentId|username|account)\b["']?)\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,;]+)/gi, '[redacted]')
      .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g, '[token redacted]')
      .substring(0, Math.max(0, Math.min(limit, 20000)))
  }
  static technical(value: string): string {
    const parts: string[] = value.split(/\n+(?:详细信息\s*[／/]\s*Details|Details)\s*\n/i)
    const detail: string = parts.length > 1 ? parts.slice(1).join('\n\n') : value
    return ErrorDiagnostics.safe(/^[A-Za-z][A-Za-z0-9_]*(?:Error|Exception)?\s*(?:\(|:)/.test(detail) ? detail : 'Error: ' + detail)
  }
  /** Presentation only: preserve the actionable sentence, keep codes and logs in the diagnostic panel. */
  static brief(value: string, summary: string = ''): string {
    if (summary) return ErrorDiagnostics.safe(summary, 240)
    let brief: string = value.split(/\n+(?:详细信息\s*[／/]\s*Details|Details)\s*\n/i)[0].split(/\nPrevious request/i)[0]
    brief = brief.replace(/^(?:[A-Za-z]\w*(?:\s*\([^)]*\))?:\s*)+/, '')
    brief = brief.replace(/^Authentication required\s*[·:：]?\s*/i, '')
    if (/^网络(?:请求|连接)(?:失败|错误)/.test(brief)) return '网络连接失败，请检查网络后重新加载。'
    brief = brief.replace(/\s*(?:Operation timeout|Failed to resolve|Parameter error|HTTP\s+\d{3}|\(?code\s*[=:]?\s*\d+|phase=)[\s\S]*$/i, '')
      .replace(/\s*[（(]?\s*https?:\/\/[\s\S]*$/i, '')
      .replace(/[（(][^）)]*(?:code|status|phase|elapsed|totalBudget)[^）)]*[）)]/gi, '').trim()
    if (!brief || !/[\u3400-\u9fff]/.test(brief) && /(?:Error|Exception|timeout|invalid|failed|status=|code=|\[object Object\])/i.test(value)) {
      return '暂时无法完成操作，请稍后重试。'
    }
    return ErrorDiagnostics.safe(brief.replace(/[:：;；(（]\s*$/, ''), 240)
  }
  static message(error: Object, summary: string = ''): string {
    if (error === null || error === undefined) return (summary || '暂时无法完成操作，请稍后重试。') + '\n\n详细信息 / Details\n' + ErrorDiagnostics.detail(error)
    const value: string | undefined = (error as DiagnosticFailure).message
    const raw: string = typeof value === 'string' ? value : String(error)
    if (raw.includes('详细信息 / Details')) return raw
    // Keep actionable site messages; English-only failures receive a Chinese
    // summary; presentation moves the original exception to its diagnostic panel.
    const brief: string = summary || (/[\u3400-\u9fff]/.test(raw) ? ErrorDiagnostics.safe(raw) : '暂时无法完成操作，请稍后重试。')
    return brief + '\n\n详细信息 / Details\n' + ErrorDiagnostics.detail(error)
  }
}
