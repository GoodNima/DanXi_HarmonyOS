/** A slow dorm backend must not be mistaken for a rejected login. Keep one
 * minute for the whole read/recovery, matching the iOS request wait window. */
export class DormRequestPolicy {
  static readonly WAIT_MS: number = 60000
  static isDorm(url: string): boolean {
    return /^https:\/\/zlapp\.fudan\.edu\.cn\//i.test(url) &&
      (/\/fudanelec\//i.test(url) || /fudanelec%2F/i.test(url))
  }
  static remaining(deadline: number): number { return Math.max(0, deadline - Date.now()) }
}
