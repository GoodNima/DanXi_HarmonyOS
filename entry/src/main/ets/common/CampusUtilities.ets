import { CampusSignal } from './CampusSignal'
import { CampusPreviewItem } from '../model/CampusPreviewItem'
import { AppState } from './AppState'
import { AppLanguage } from './AppLanguage'
import { CampusCookies } from './CampusCookies'
import { CampusService } from './CampusService'
import { ForumRepository } from '../repository/ForumRepository'
import { FduRepository } from '../repository/FduRepository'
import { CampusUtilityRepository } from '../repository/CampusUtilityRepository'
import { ReservationRepository } from '../repository/ReservationRepository'
import { CourseReviewRepository } from '../repository/CourseReviewRepository'
import { CampusUtilitySummary, CampusAccessCard, SportsSnapshot, LifeCode } from '../model/CampusUtility'

export class CampusUtilitySnapshot {
  access: CampusAccessCard[] = []
  sports: SportsSnapshot = new SportsSnapshot()
  code: LifeCode = new LifeCode()
  updatedAt: number = 0
  status: string = 'ready'
}

/** Protected summaries only reuse verified sessions. An explicit detail read
 * acquires/renews its service through the same serialized browser SSO queue. */
export class CampusUtilities {
  private static cache: Map<string, CampusUtilitySummary> = new Map<string, CampusUtilitySummary>()
  private static pending: Map<string, Promise<CampusUtilitySummary>> = new Map<string, Promise<CampusUtilitySummary>>()
  private static cacheScope: string = ''
  private static readonly details: Map<string, CampusUtilitySnapshot> = new Map<string, CampusUtilitySnapshot>()
  private static readonly detailFlights: Map<string, Promise<CampusUtilitySnapshot>> = new Map<string, Promise<CampusUtilitySnapshot>>()
  static supported(feature: string): boolean { return ['evaluation', 'campus_access', 'sports', 'life_code'].includes(feature) }
  static scope(feature: string): string {
    if (feature === 'evaluation') return 'forum/' + String(ForumRepository.getInstance().sessionRevision()) + '/' + String(ForumRepository.getInstance().isLoggedIn())
    const person = AppState.getPerson()
    return person.getStudentId() + '/' + String(person.isLoggedIn()) + '/' + person.academicGroup + '/' + String(CampusCookies.generation())
  }
  static title(feature: string): Resource {
    if (feature === 'evaluation') return $r('app.string.utility_evaluation')
    if (feature === 'campus_access') return $r('app.string.utility_access')
    if (feature === 'life_code') return $r('app.string.utility_life_code')
    return $r('app.string.utility_sports')
  }
  static load(feature: string, force: boolean = false): Promise<CampusUtilitySnapshot> {
    const owner: string = CampusUtilities.scope(feature)
    const key: string = owner + '/' + feature
    const cached: CampusUtilitySnapshot | undefined = CampusUtilities.details.get(key)
    if (feature !== 'life_code' && !force && cached !== undefined && Date.now() - cached.updatedAt < 5 * 60000) return Promise.resolve(cached)
    const pending: Promise<CampusUtilitySnapshot> | undefined = CampusUtilities.detailFlights.get(key)
    if (pending !== undefined) return pending
    const task: Promise<CampusUtilitySnapshot> = CampusUtilities.readDetail(feature, owner).then((value: CampusUtilitySnapshot): CampusUtilitySnapshot => {
      // A payment credential is never cached beyond its visible page.
      if (feature !== 'life_code') CampusUtilities.details.set(key, value)
      while (CampusUtilities.details.size > 16) {
        const first: string | undefined = CampusUtilities.details.keys().next().value
        if (first !== undefined) CampusUtilities.details.delete(first)
      }
      return value
    }).finally(() => { if (CampusUtilities.detailFlights.get(key) === task) CampusUtilities.detailFlights.delete(key) })
    CampusUtilities.detailFlights.set(key, task)
    return task
  }
  private static async readDetail(feature: string, owner: string): Promise<CampusUtilitySnapshot> {
    if (!CampusUtilities.supported(feature) || feature === 'evaluation') throw new Error(AppLanguage.text($r('app.string.utility_invalid_service')))
    const repo = FduRepository.getInstance()
    const snapshot = new CampusUtilitySnapshot()
    if (feature === 'campus_access') snapshot.access = await repo.withService(CampusService.MY_FUDAN, async cookies => CampusUtilityRepository.access(cookies))
    else if (feature === 'sports') {
      // The 2026 official system moved to a mini program. Only an existing
      // verified legacy cookie can read the original web record; never launch
      // the retired UIS/tac verification chain or invent a new web API.
      const cookies = repo.cookiesFor(CampusService.SPORTS)
      if (AppState.getPerson().isLoggedIn() && cookies) snapshot.sports = await CampusUtilityRepository.sports(cookies)
      else snapshot.status = 'migrated'
    }
    else snapshot.code = await repo.withService(CampusService.LIFE_CODE, async cookies => CampusUtilityRepository.lifeCode(cookies))
    CampusUtilities.guard(feature, owner)
    snapshot.updatedAt = Date.now()
    return snapshot
  }
  static preview(feature: string, force: boolean = false): Promise<CampusUtilitySummary> {
    if (!CampusUtilities.supported(feature)) return Promise.reject(new Error(AppLanguage.text($r('app.string.utility_invalid_service'))))
    const owner = CampusUtilities.scope(feature)
    // Clear the old campus scope as soon as a user switches/logs out. Forum
    // summaries are likewise keyed to its independent session generation.
    const allScope = CampusUtilities.scope('sports') + '/' + CampusUtilities.scope('evaluation')
    if (allScope !== CampusUtilities.cacheScope) { CampusUtilities.cache.clear(); CampusUtilities.cacheScope = allScope }
    const key = owner + '/' + AppLanguage.current() + '/' + feature
    const cached = CampusUtilities.cache.get(key)
    if (!force && cached !== undefined && Date.now() - cached.updatedAt < 5 * 60000) return Promise.resolve(CampusUtilities.copy(cached))
    const existing = CampusUtilities.pending.get(key)
    if (existing !== undefined) return existing
    const task = CampusUtilities.readPreview(feature, owner).then((row: CampusUtilitySummary): CampusUtilitySummary => {
      CampusUtilities.guard(feature, owner)
      if (row.updatedAt > 0) CampusUtilities.cache.set(key, CampusUtilities.copy(row))
      return row
    }).finally(() => { if (CampusUtilities.pending.get(key) === task) CampusUtilities.pending.delete(key) })
    CampusUtilities.pending.set(key, task)
    return task
  }
  private static async readPreview(feature: string, owner: string): Promise<CampusUtilitySummary> {
    const row = new CampusUtilitySummary(); row.feature = feature
    const repo = FduRepository.getInstance()
    if (feature === 'evaluation') {
      if (!ForumRepository.getInstance().isLoggedIn()) return CampusUtilities.login(row, true)
      const review = await CourseReviewRepository.random(true)
      CampusUtilities.guard(feature, owner)
      row.value = review.courseName || review.title
      row.description = review.title
      row.secondary = review.teacher
    } else {
      if (feature === 'sports') {
        // The campus card is an entry, not an availability probe. Reuse the
        // venue catalog after an explicit visit without background SSO reads.
        const places = ReservationRepository.cached()
        row.value = places === undefined ? AppLanguage.text($r('app.string.reservation_choose_place')) :
          AppLanguage.text($r('app.string.reservation_place_count'), 0, String(places.length))
        row.description = AppLanguage.text($r('app.string.reservation_preview_hint'))
        row.secondary = places?.slice(0, 2).map((place) => place.name).join(' · ') ?? ''
        row.updatedAt = Date.now(); return row
      }
      if (!AppState.getPerson().isLoggedIn()) return CampusUtilities.login(row, false)
      const service = feature === 'campus_access' ? CampusService.MY_FUDAN : feature === 'sports' ? CampusService.SPORTS : CampusService.LIFE_CODE
      const cookies = repo.cookiesFor(service)
      if (!cookies) return CampusUtilities.login(row, false)
      if (feature === 'life_code') {
        // A rotating payment credential is fetched only in its explicit page.
        row.value = AppLanguage.text($r('app.string.utility_code_entry'))
        row.description = AppLanguage.text($r('app.string.utility_code_preview_hint'))
      } else if (feature === 'campus_access') {
        const cards = await CampusUtilityRepository.access(cookies)
        CampusUtilities.guard(feature, owner)
        if (cards.length === 0) { row.status = 'empty'; row.value = AppLanguage.text($r('app.string.utility_no_access')) }
        else {
          const permissions: string[] = cards.map(card => card.permission)
          row.tone = CampusSignal.permissions(permissions)
          row.value = permissions.filter(value => value.length > 0).join(' / ') || AppLanguage.text($r('app.string.utility_not_provided'))
          row.description = cards.map(card => card.status).filter(text => text.length > 0).join(' / ')
          row.secondary = cards[0].expireDate
        }
      } else {
        const snapshot = await CampusUtilityRepository.sports(cookies)
        CampusUtilities.guard(feature, owner)
        const values = [snapshot.category(0), snapshot.category(1), snapshot.category(2)]
        row.value = AppLanguage.text($r('app.string.utility_sports_summary'), 0,
          values[0] === undefined ? '—' : String(values[0]), values[1] === undefined ? '—' : String(values[1]), values[2] === undefined ? '—' : String(values[2]))
        row.description = snapshot.items.slice(0, 3).map(item => item.title + ' ' + (item.times === undefined ? '—' : String(item.times))).join(' / ')
        if (snapshot.items.length === 0) row.status = 'empty'
      }
    }
    row.updatedAt = Date.now(); return row
  }
  private static login(row: CampusUtilitySummary, forum: boolean): CampusUtilitySummary {
    row.status = 'login'; row.updatedAt = 0
    row.value = AppLanguage.text($r('app.string.utility_login_value'))
    row.description = AppLanguage.text(forum ? $r('app.string.utility_forum_login_hint') : $r('app.string.utility_campus_login_hint'))
    return row
  }
  private static guard(feature: string, owner: string): void {
    if (owner !== CampusUtilities.scope(feature)) throw new Error(AppLanguage.text($r('app.string.utility_account_changed')))
  }
  private static copy(source: CampusUtilitySummary): CampusUtilitySummary {
    const row = new CampusUtilitySummary(); row.feature = source.feature; row.value = source.value
    row.description = source.description; row.secondary = source.secondary; row.updatedAt = source.updatedAt; row.status = source.status; row.tone = source.tone
    row.items = CampusPreviewItem.copy(source.items)
    return row
  }
}
