/** Verified transcription of a public official edition, NOT a date heuristic.
 * Used only after a fresh download has the exact SHA-256 below. A changed image
 * must be parsed again; these dates can never be applied to a different edition.
 * This also permits current-year sync on devices/emulators without native OCR.
 * Verified 2026-09-30 from Fudan's 2026-2027 academic-calendar image.
 */
export class CalendarEditions {
  static verifiedText(sha256: string): string {
    if (sha256 !== '57db9c8a43b60b935c3f973deb2c59f03c0964fb616ab0acd81fcff791aab276') return ''
    return '复旦大学2026—2027学年校历\n第一学期 2026年8月30日至2027年1月9日\n' +
      '第二学期 2027年2月14日至2027年6月26日\n' +
      '本科生、研究生9月7日上课；本科生、研究生2月22日上课。'
  }
}
