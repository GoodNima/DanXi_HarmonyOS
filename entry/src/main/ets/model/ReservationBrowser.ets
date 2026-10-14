import { ReservationParser } from './Reservation'

export interface ReservationBrowserDocument { url: string; html: string }

/** A normal official WebView performs the site's own checks; it neither
 * synthesises security cookies nor treats HTTP 412 as a failed campus login. */
export class ReservationBrowser {
  static allowed(url: string): boolean {
    return /^https:\/\/elife\.fudan\.edu\.cn\/public\/front\/(?:search|getResource2)\.htm(?:\?|$)/.test(url)
  }
  static ready(requested: string, document: ReservationBrowserDocument): boolean {
    if (typeof document.url !== 'string' || typeof document.html !== 'string') return false
    if (!ReservationBrowser.allowed(requested) || !ReservationBrowser.allowed(document.url) || document.html.length > 2 * 1024 * 1024) return false
    const query = (url: string, key: string): string => new RegExp('[?&]' + key + '=([^&]*)').exec(url)?.[1] ?? ''
    if (requested.includes('/search.htm')) return document.url.includes('/search.htm') &&
      query(requested, 'id') === query(document.url, 'id') && /class\s*=\s*["'][^"']*\border_list\b/.test(document.html)
    return document.url.includes('/getResource2.htm') && query(requested, 'contentId') === query(document.url, 'contentId') &&
      query(requested, 'currentDate') === query(document.url, 'currentDate') &&
      (/id\s*=\s*["']con_one_1["']/.test(document.html) || document.html.includes('无可预约场地'))
  }
  static readonly SCRIPT: string = 'JSON.stringify({url:location.href,html:document.documentElement.outerHTML})'
  static readonly HOME: string = ReservationParser.ORIGIN + '/public/front/search.htm?id=' + ReservationParser.CATEGORIES[0]
}
