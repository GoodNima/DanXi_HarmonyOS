/**
 * Service callback URLs and browser entry pages, compared with upstream DanXi.
 * CAS tickets belong to one callback; the resulting service sessions belong to
 * their host. The browser's domain/path-aware jar shares SSO across callbacks.
 */
import { FduAuthPolicy } from '../model/FduAuth'

export class CampusService {
  /** A CAS ticket is per callback URL, but the resulting web session is per host. */
  static sessionKey(service: string): string {
    return FduAuthPolicy.origin(service) || service
  }

  /** Open the actual service page so the shared browser jar drives its own SSO. */
  static entryUrl(service: string): string {
    // The booking homepage is public. Only its login callback redeems shared
    // campus SSO and establishes the protected JSON API's session.
    if (service.startsWith('https://booking.fudan.edu.cn/reservation/api/login/main')) return service
    if (service === CampusService.EHALL) return 'https://ehall.fudan.edu.cn/'
    if (service === CampusService.ECARD) return 'https://ecard.fudan.edu.cn/epay/myepay/index'
    if (service === CampusService.BUS) return 'https://zlapp.fudan.edu.cn/fudanbus/wap/default/lists'
    if (service === CampusService.DORM) return 'https://zlapp.fudan.edu.cn/fudanelec/wap/default/info'
    if (service === CampusService.EXAM) return 'https://fdjwgl.fudan.edu.cn/student/for-std/exam-arrange'
    if (service === CampusService.GPA) return 'https://fdjwgl.fudan.edu.cn/student/for-std/grade/my-gpa'
    if (service === CampusService.TIMETABLE) return 'https://fdjwgl.fudan.edu.cn/student/for-std/course-table'
    return service
  }

  /** Upstream primary account login and authenticated student profile. */
  static readonly EHALL: string = 'https://ehall.fudan.edu.cn/manage/common/login/index?redirect=https%3A%2F%2Fehall.fudan.edu.cn'
  /** Dining and electricity history have their own protected service session. */
  static readonly MY_FUDAN: string = 'https://my.fudan.edu.cn/simple_list/stqk'
  /** Legacy sports data remains a compatibility read. UIS/tac stopped serving
   * in July 2026; current students use the official smart-sports mini program. */
  static readonly SPORTS: string = 'https://fdtyjw.fudan.edu.cn/sportScore/stScore.aspx'
  /** The iOS reservation flow authenticates through elife's own login callback. */
  static readonly RESERVATION: string = 'https://elife.fudan.edu.cn/login2.action'
  static cookieUrl(service: string): string { return service === CampusService.SPORTS ? CampusService.SPORTS : CampusService.entryUrl(service) }

  /** campus card. See CardRepository, which consumes a session for this one. */
  static readonly ECARD: string =
    'https://ecard.fudan.edu.cn/epay/j_spring_cas_security_check'

  /** QR Code is a separate protected path; an epay home landing does not
   * establish its path-scoped session. The host SSO cookies remain shared. */
  static readonly LIFE_CODE: string = 'https://ecard.fudan.edu.cn/epay/wxpage/fudan/zfm/qrcode'

  /**
   * Campus bus. The service is zlapp's own SSO wrapper carrying the real target
   * in `redirect=` — asking CAS for `/fudanbus/wap/default/lists` directly is
   * refused.
   */
  static readonly BUS: string =
    'https://zlapp.fudan.edu.cn/a_fudanzlapp/api/sso/index' +
    '?redirect=https%3A%2F%2Fzlapp.fudan.edu.cn%2Ffudanbus%2Fwap%2Fdefault%2Flists&from=wap'

  /** Dormitory electricity, same wrapper, different redirect target. */
  static readonly DORM: string =
    'https://zlapp.fudan.edu.cn/a_fudanzlapp/api/sso/index' +
    '?redirect=https%3A%2F%2Fzlapp.fudan.edu.cn%2Ffudanelec%2Fwap%2Fdefault%2Finfo&from=wap'

  /**
   * Timetable. fdjwgl puts the destination in `refer=`, so each of the three
   * academic endpoints has its own callback string, but the final JSESSIONID
   * is shared by the academic host.
   */
  static readonly TIMETABLE: string =
    'https://fdjwgl.fudan.edu.cn/student/sso/login' +
    '?refer=https://fdjwgl.fudan.edu.cn/student/for-std/course-table'

  static readonly EXAM: string =
    'https://fdjwgl.fudan.edu.cn/student/sso/login' +
    '?refer=https://fdjwgl.fudan.edu.cn/student/for-std/exam-arrange'

  static readonly GPA: string =
    'https://fdjwgl.fudan.edu.cn/student/sso/login' +
    '?refer=https://fdjwgl.fudan.edu.cn/student/for-std/grade/my-gpa'
}
