import { ForumRepository } from './ForumRepository'
import { ForumNetwork } from '../common/ForumNetwork'
import { Constant } from '../common/Constant'
import { AppLanguage } from '../common/AppLanguage'
import { ForumPreferences } from '../common/ForumPreferences'
import { CourseReviewCatalogStore } from '../common/CourseReviewCatalogStore'
import { CourseReviewPreview, CourseReviewPreviewParser } from '../common/CourseReviewPreviewParser'
import { readCourseReviewPreview } from '../common/CourseReviewPreviewTask'
import { HttpError, HttpResponse } from '../util/HttpUtil'
import { CourseReviewGroup, CourseReview, CourseReviewDraft, CourseReviewSearch, ReviewRating, ReviewCourse, ReviewVoteBody, CourseReviewSummary } from '../model/CourseReview'

class CourseDetailEntry {
  group: CourseReviewGroup = new CourseReviewGroup()
  at: number = 0
}

/** Shares DanKe's upstream forum JWT, refresh handler and WebVPN routing.
 * Only account-scoped directory metadata is persisted; reviews remain in memory. */
export class CourseReviewRepository {
  private static readonly SIZE: number = 20
  private static catalogRevision: number = -1
  private static catalogRows: CourseReviewGroup[] | null = null
  private static catalogHash: string = ''
  private static catalogFlight: Promise<CourseReviewGroup[]> | null = null
  private static catalogBackground: boolean = false
  private static catalogReadEpoch: number = 0
  private static catalogRestored: boolean = false
  private static catalogRestoreFlight: Promise<void> | null = null
  private static catalogChecked: boolean = false
  private static catalogListeners: Set<() => void> = new Set<() => void>()
  private static detailRevision: number = -1
  private static detailCache: Map<number, CourseDetailEntry> = new Map<number, CourseDetailEntry>()
  private static detailFlights: Map<number, Promise<CourseReviewGroup>> = new Map<number, Promise<CourseReviewGroup>>()
  private static summaryCache: Map<number, CourseDetailEntry> = new Map<number, CourseDetailEntry>()
  private static summaryFlights: Map<number, Promise<CourseReviewGroup>> = new Map<number, Promise<CourseReviewGroup>>()
  private static detailEpoch: number = 0
  private static invalidateDetails(): void {
    CourseReviewRepository.detailEpoch++
    CourseReviewRepository.detailCache.clear(); CourseReviewRepository.detailFlights.clear()
    CourseReviewRepository.summaryCache.clear(); CourseReviewRepository.summaryFlights.clear()
  }
  static async random(previewOnly: boolean = false): Promise<CourseReview> {
    const revision = await CourseReviewRepository.session()
    const response = await ForumNetwork.getInstance().get(Constant.DANKE_BASE_URL + '/reviews/random', undefined, undefined, 15000, !previewOnly)
    CourseReviewRepository.guard(revision)
    return CourseReviewRepository.parseReview(CourseReviewRepository.object(response.data))
  }
  static async search(keyword: string, page: number = 1, force: boolean = false): Promise<CourseReviewSearch> {
    if (!Number.isInteger(page) || page < 1) throw new Error(AppLanguage.text($r('app.string.utility_invalid_identifier')))
    // Swift's home uses the complete /courses directory, not an empty search
    // (the v3 search endpoint explicitly rejects an empty query).
    if (force && page === 1) CourseReviewRepository.invalidateDetails()
    if (!keyword.trim()) return CourseReviewRepository.catalog(page, force)
    const revision = await CourseReviewRepository.session()
    if (force && page === 1 && CourseReviewRepository.catalogRevision === revision) CourseReviewRepository.invalidateCatalogSummaries()
    const response = await ForumNetwork.getInstance().get(Constant.DANKE_BASE_URL + '/v3/course_groups/search',
      { 'query': keyword.trim(), 'page': String(page), 'page_size': String(CourseReviewRepository.SIZE) })
    CourseReviewRepository.guard(revision)
    const result = CourseReviewRepository.parseSearch(response.data)
    if (CourseReviewRepository.catalogRevision === revision) {
      for (const group of result.items) {
        const cached = CourseReviewRepository.catalogRows?.find(row => row.id === group.id)
        if (!force && cached !== undefined && cached.summary.ready) {
          group.summary = cached.summary; group.reviewCount = cached.summary.count
        }
      }
    }
    return result
  }
  private static async catalog(page: number, force: boolean): Promise<CourseReviewSearch> {
    const revision = await CourseReviewRepository.session()
    if (CourseReviewRepository.catalogRevision !== revision) {
      CourseReviewRepository.catalogRevision = revision
      CourseReviewRepository.catalogRows = null; CourseReviewRepository.catalogHash = ''; CourseReviewRepository.catalogFlight = null
      CourseReviewRepository.catalogReadEpoch++; CourseReviewRepository.catalogRestored = false
      CourseReviewRepository.catalogRestoreFlight = null; CourseReviewRepository.catalogChecked = false
    }
    await CourseReviewRepository.restoreCatalog(revision)
    CourseReviewRepository.guard(revision)
    if (CourseReviewRepository.catalogRows === null || (force && page === 1)) {
      const previous = CourseReviewRepository.catalogRows
      const background = CourseReviewRepository.catalogFlight !== null && CourseReviewRepository.catalogBackground
      let task = CourseReviewRepository.requestCatalog(revision, true, force)
      try { await task } catch (e) {
        // An explicit refresh can continue authentication that a passive cached
        // directory check deliberately did not open. Concurrent taps still join.
        if (!force || !background) throw e as Error
        CourseReviewRepository.guard(revision)
        if (CourseReviewRepository.catalogFlight === task) CourseReviewRepository.catalogFlight = null
        task = CourseReviewRepository.requestCatalog(revision, true, force)
        await task
      }
      if (force && background && previous === CourseReviewRepository.catalogRows) CourseReviewRepository.invalidateCatalogSummaries()
    } else CourseReviewRepository.revalidateCatalog()
    CourseReviewRepository.guard(revision)
    const result = new CourseReviewSearch(); result.page = page; result.pageSize = CourseReviewRepository.SIZE
    result.items = (CourseReviewRepository.catalogRows ?? []).slice((page - 1) * result.pageSize, page * result.pageSize)
    return result
  }
  static subscribeCatalog(listener: () => void): () => void {
    CourseReviewRepository.catalogListeners.add(listener)
    return (): void => { CourseReviewRepository.catalogListeners.delete(listener) }
  }
  static cachedCatalogPages(pages: number): CourseReviewSearch | null {
    const forum = ForumRepository.getInstance()
    if (!forum.isLoggedIn() || forum.sessionRevision() !== CourseReviewRepository.catalogRevision ||
      CourseReviewRepository.catalogRows === null || !Number.isInteger(pages) || pages < 1) return null
    const result = new CourseReviewSearch(); result.page = pages; result.pageSize = CourseReviewRepository.SIZE
    result.items = CourseReviewRepository.catalogRows.slice(0, pages * CourseReviewRepository.SIZE)
    return result
  }
  static revalidateCatalog(): void {
    const forum = ForumRepository.getInstance()
    if (!forum.isLoggedIn() || forum.sessionRevision() !== CourseReviewRepository.catalogRevision ||
      CourseReviewRepository.catalogRows === null || CourseReviewRepository.catalogFlight !== null ||
      CourseReviewRepository.catalogChecked) return
    CourseReviewRepository.requestCatalog(forum.sessionRevision(), false, false).catch(() => {})
  }
  private static requestCatalog(revision: number, allowAuthentication: boolean, force: boolean): Promise<CourseReviewGroup[]> {
    if (CourseReviewRepository.catalogFlight !== null) return CourseReviewRepository.catalogFlight
    CourseReviewRepository.catalogChecked = true; CourseReviewRepository.catalogBackground = !allowAuthentication
    const task = CourseReviewRepository.readCatalog(revision, allowAuthentication, force)
    CourseReviewRepository.catalogFlight = task
    task.finally(() => {
      if (CourseReviewRepository.catalogFlight === task) CourseReviewRepository.catalogFlight = null
    }).catch(() => {})
    return task
  }
  private static async restoreCatalog(revision: number): Promise<void> {
    if (CourseReviewRepository.catalogRestored) return
    if (CourseReviewRepository.catalogRestoreFlight === null) {
      const task: Promise<void> = CourseReviewCatalogStore.load(CourseReviewRepository.catalogOwner()).then(snapshot => {
        CourseReviewRepository.guard(revision)
        if (snapshot !== null && CourseReviewRepository.catalogRows === null) {
          CourseReviewRepository.catalogRows = CourseReviewCatalogStore.groups(snapshot)
          CourseReviewRepository.catalogHash = snapshot.hash
        }
        CourseReviewRepository.catalogRestored = true
      })
      CourseReviewRepository.catalogRestoreFlight = task
      task.finally(() => {
        if (CourseReviewRepository.catalogRestoreFlight === task) CourseReviewRepository.catalogRestoreFlight = null
      }).catch(() => {})
    }
    await CourseReviewRepository.catalogRestoreFlight
  }
  private static catalogOwner(): number { return AppStorage.get<number>(ForumPreferences.USER_ID) ?? 0 }
  private static persistCatalog(rows: CourseReviewGroup[], revision: number, epoch: number): void {
    const owner = CourseReviewRepository.catalogOwner()
    CourseReviewCatalogStore.save(owner, rows, CourseReviewRepository.catalogHash, (): boolean => {
      const forum = ForumRepository.getInstance()
      return forum.isLoggedIn() && forum.sessionRevision() === revision && CourseReviewRepository.catalogOwner() === owner &&
        CourseReviewRepository.catalogReadEpoch === epoch && CourseReviewRepository.catalogRows === rows
    }).catch(() => {})
  }
  private static publishCatalog(): void {
    for (const listener of CourseReviewRepository.catalogListeners) { try { listener() } catch (e) {} }
  }
  private static invalidateCatalogSummaries(): void {
    for (const row of CourseReviewRepository.catalogRows ?? []) {
      row.reviewCount = undefined; row.summary = new CourseReviewSummary()
      for (const course of row.courses) { course.reviews = []; course.reviewsLoaded = false }
    }
  }
  private static async readCatalog(revision: number, allowAuthentication: boolean, force: boolean): Promise<CourseReviewGroup[]> {
    const network = ForumNetwork.getInstance()
    const epoch: number = ++CourseReviewRepository.catalogReadEpoch
    if (CourseReviewRepository.catalogRows === null) {
      // Fetch only the directory on a cache miss. A concurrently returned hash
      // could describe a newer directory and permanently label old rows as fresh.
      // Leave it unknown until a later hash-then-directory check establishes it.
      const response = await network.get(Constant.DANKE_BASE_URL + '/courses', undefined, undefined, 15000, allowAuthentication)
      CourseReviewRepository.guard(revision)
      const rows = CourseReviewRepository.parseCatalog(response.data)
      CourseReviewRepository.catalogRows = rows; CourseReviewRepository.catalogHash = ''
      CourseReviewRepository.persistCatalog(rows, revision, epoch)
      return rows
    }
    let hash: string = ''
    try {
      const hashResponse = await network.get(Constant.DANKE_BASE_URL + '/courses/hash', undefined, undefined, 15000, allowAuthentication)
      hash = CourseReviewRepository.text(CourseReviewRepository.object(hashResponse.data)['hash'])
    } catch (e) {
      // An auxiliary hash failure cannot suppress a valid directory response.
      if (e instanceof HttpError && (e.statusCode === -2 || e.statusCode === 401 || e.statusCode === 403)) throw e as Error
    }
    CourseReviewRepository.guard(revision)
    if (hash && CourseReviewRepository.catalogRows !== null && hash === CourseReviewRepository.catalogHash) {
      // The directory hash does not guarantee unchanged evaluations. An
      // explicit refresh invalidates old review summaries, including zero.
      if (force) CourseReviewRepository.invalidateCatalogSummaries()
      CourseReviewRepository.persistCatalog(CourseReviewRepository.catalogRows, revision, epoch)
      return CourseReviewRepository.catalogRows
    }
    const response = await network.get(Constant.DANKE_BASE_URL + '/courses', undefined, undefined, 15000, allowAuthentication)
    CourseReviewRepository.guard(revision)
    const rows = CourseReviewRepository.parseCatalog(response.data)
    CourseReviewRepository.catalogRows = rows; CourseReviewRepository.catalogHash = hash
    CourseReviewRepository.persistCatalog(rows, revision, epoch)
    CourseReviewRepository.publishCatalog()
    return rows
  }
  static parseCatalog(body: string): CourseReviewGroup[] {
    let value: Object
    try { value = JSON.parse(body) as Object } catch (e) { throw new HttpError(200, 0, AppLanguage.text($r('app.string.utility_invalid_response')), '') }
    if (!Array.isArray(value)) throw new HttpError(200, 0, AppLanguage.text($r('app.string.utility_invalid_response')), '')
    const ids: Set<number> = new Set<number>()
    return (value as Object[]).map(item => {
      // The Swift directory has camelCase legacy keys; v3 detail/search use snake_case.
      const raw = CourseReviewRepository.record(item)
      if (Array.isArray(raw['courseList'])) raw['course_list'] = raw['courseList']
      const group = CourseReviewRepository.parseGroup(raw, false)
      if (Array.isArray(raw['course_list'])) {
        group.courseCount = group.courses.length
        if (group.credits.length === 0) group.credits = Array.from(new Set<number>(group.courses
          .filter(course => course.credit !== undefined).map(course => course.credit as number)))
      }
      return group
    }).filter(group => { if (ids.has(group.id)) return false; ids.add(group.id); return true })
  }
  /** Passive list reads retain only compact aggregates, never a partial detail. */
  static async summary(id: number): Promise<CourseReviewGroup> {
    CourseReviewRepository.requireId(id)
    const revision = await CourseReviewRepository.session()
    if (CourseReviewRepository.detailRevision !== revision) {
      CourseReviewRepository.detailRevision = revision
      CourseReviewRepository.invalidateDetails()
    }
    const epoch: number = CourseReviewRepository.detailEpoch
    const detail = CourseReviewRepository.detailCache.get(id)
    const cached = detail !== undefined && detail.group.summary.ready && Date.now() - detail.at < 120000 ? detail : CourseReviewRepository.summaryCache.get(id)
    if (cached !== undefined && Date.now() - cached.at < 120000) {
      CourseReviewRepository.rememberListSummary(cached.group, revision, epoch)
      return cached.group
    }
    const pending = CourseReviewRepository.summaryFlights.get(id)
    if (pending !== undefined) return pending
    const task = CourseReviewRepository.readSummary(id, revision, epoch)
    CourseReviewRepository.summaryFlights.set(id, task)
    try { return await task } finally {
      if (CourseReviewRepository.summaryFlights.get(id) === task) CourseReviewRepository.summaryFlights.delete(id)
    }
  }
  private static async readSummary(id: number, revision: number, epoch: number): Promise<CourseReviewGroup> {
    const network = ForumNetwork.getInstance()
    let response: HttpResponse
    try { response = await network.get(Constant.DANKE_BASE_URL + '/group/' + id, undefined, undefined, 15000, false) }
    catch (e) {
      if (!(e instanceof HttpError) || (e.statusCode !== 404 && e.statusCode !== 405)) throw e as Error
      CourseReviewRepository.guard(revision)
      response = await network.get(Constant.DANKE_BASE_URL + '/v3/course_groups/' + id, undefined, undefined, 15000, false)
    }
    CourseReviewRepository.guard(revision)
    const preview = await readCourseReviewPreview(response.data)
    CourseReviewRepository.guard(revision)
    if (preview.id !== id) throw new HttpError(200, 0, AppLanguage.text($r('app.string.utility_invalid_response')), '')
    if (!preview.summary.ready) {
      await CourseReviewRepository.hydrateSummary(preview, revision)
      CourseReviewPreviewParser.summarize(preview)
    }
    CourseReviewRepository.guard(revision)
    const group = new CourseReviewGroup(); group.id = preview.id; group.name = preview.name
    group.summary = preview.summary; group.reviewCount = preview.summary.count
    if (epoch === CourseReviewRepository.detailEpoch) {
      const entry = new CourseDetailEntry(); entry.group = group; entry.at = Date.now()
      CourseReviewRepository.summaryCache.delete(id); CourseReviewRepository.summaryCache.set(id, entry)
      while (CourseReviewRepository.summaryCache.size > 128) CourseReviewRepository.summaryCache.delete(CourseReviewRepository.summaryCache.keys().next().value as number)
      CourseReviewRepository.rememberListSummary(group, revision, epoch)
    }
    return group
  }
  private static async hydrateSummary(preview: CourseReviewPreview, revision: number): Promise<void> {
    const courses = preview.courses.filter(course => !course.loaded)
    let next: number = 0
    let failed: boolean = false
    const reader = async (): Promise<void> => {
      while (!failed && next < courses.length) {
        const course = courses[next++]
        try {
          CourseReviewRepository.guard(revision)
          const response = await ForumNetwork.getInstance().get(Constant.DANKE_BASE_URL + '/courses/' + course.id + '/reviews',
            undefined, undefined, 15000, false)
          CourseReviewRepository.guard(revision)
          const result = await readCourseReviewPreview(response.data, true)
          CourseReviewRepository.guard(revision)
          const aggregate = result.courses[0]
          course.count = aggregate.count; course.rankCount = aggregate.rankCount; course.rankTotal = aggregate.rankTotal; course.loaded = true
        } catch (e) { failed = true; throw e as Error }
      }
    }
    await Promise.all([reader(), reader()])
  }
  static async group(id: number, force: boolean = false, previewOnly: boolean = false): Promise<CourseReviewGroup> {
    CourseReviewRepository.requireId(id)
    const revision = await CourseReviewRepository.session()
    if (CourseReviewRepository.detailRevision !== revision) {
      CourseReviewRepository.detailRevision = revision
      CourseReviewRepository.invalidateDetails()
    }
    if (force) CourseReviewRepository.invalidateDetails()
    const epoch: number = CourseReviewRepository.detailEpoch
    const cached = CourseReviewRepository.detailCache.get(id)
    if (!force && cached !== undefined && Date.now() - cached.at < 120000) {
      if (previewOnly) CourseReviewRepository.rememberListSummary(cached.group, revision, epoch)
      return cached.group
    }
    const pending = CourseReviewRepository.detailFlights.get(id)
    if (pending !== undefined) {
      const group = await pending
      CourseReviewRepository.guard(revision)
      if (previewOnly) CourseReviewRepository.rememberListSummary(group, revision, epoch)
      return group
    }
    const task = CourseReviewRepository.readGroup(id, revision, previewOnly, CourseReviewRepository.detailEpoch)
    CourseReviewRepository.detailFlights.set(id, task)
    try {
      const group = await task
      CourseReviewRepository.guard(revision)
      if (previewOnly) CourseReviewRepository.rememberListSummary(group, revision, epoch)
      return group
    } finally {
      if (CourseReviewRepository.detailFlights.get(id) === task) CourseReviewRepository.detailFlights.delete(id)
    }
  }
  private static rememberListSummary(group: CourseReviewGroup, revision: number, epoch: number): void {
    if (epoch !== CourseReviewRepository.detailEpoch || CourseReviewRepository.catalogRevision !== revision || !group.summary.ready) return
    const cached = CourseReviewRepository.catalogRows?.find(row => row.id === group.id)
    // Only a list's first read may fill its snapshot. Later detail reads keep
    // their own cache and must not silently replace visible list information.
    if (cached !== undefined && !cached.summary.ready) { cached.summary = group.summary; cached.reviewCount = group.summary.count }
  }
  private static async readGroup(id: number, revision: number, previewOnly: boolean, epoch: number): Promise<CourseReviewGroup> {
    const network = ForumNetwork.getInstance()
    let response: HttpResponse
    try {
      // Swift's group response normally includes reviews. Preview readers use
      // it directly instead of first requesting metadata from v3.
      response = await network.get(Constant.DANKE_BASE_URL + (previewOnly ? '/group/' : '/v3/course_groups/') + id,
        undefined, undefined, 15000, !previewOnly)
    } catch (e) {
      if (!previewOnly || !(e instanceof HttpError) || (e.statusCode !== 404 && e.statusCode !== 405)) throw e as Error
      CourseReviewRepository.guard(revision)
      response = await network.get(Constant.DANKE_BASE_URL + '/v3/course_groups/' + id,
        undefined, undefined, 15000, false)
    }
    CourseReviewRepository.guard(revision)
    let group = CourseReviewRepository.parseGroup(CourseReviewRepository.object(response.data), true)
    if (group.id !== id) throw new HttpError(200, 0, AppLanguage.text($r('app.string.utility_invalid_response')), '')
    if (!group.summary.ready) {
      // Some v3 responses only include course metadata. Swift's original group
      // endpoint carries reviewList; missing lists must never become fake zeros.
      if (!previewOnly) try {
        const legacy = await ForumNetwork.getInstance().get(Constant.DANKE_BASE_URL + '/group/' + id,
          undefined, undefined, 15000, !previewOnly)
        CourseReviewRepository.guard(revision)
        group = CourseReviewRepository.parseGroup(CourseReviewRepository.object(legacy.data), true)
        if (group.id !== id) throw new HttpError(200, 0, AppLanguage.text($r('app.string.utility_invalid_response')), '')
      } catch (e) {
        if (!(e instanceof HttpError) || (e.statusCode !== 404 && e.statusCode !== 405)) throw e as Error
      }
      await CourseReviewRepository.hydrateReviews(group, revision, previewOnly)
      CourseReviewRepository.attachReviewContext(group)
      group.summary = CourseReviewSummary.from(group)
    }
    if (epoch !== CourseReviewRepository.detailEpoch) return group
    const entry = new CourseDetailEntry(); entry.group = group; entry.at = Date.now()
    CourseReviewRepository.detailCache.delete(id); CourseReviewRepository.detailCache.set(id, entry)
    while (CourseReviewRepository.detailCache.size > 24) CourseReviewRepository.detailCache.delete(CourseReviewRepository.detailCache.keys().next().value as number)
    return group
  }
  private static async hydrateReviews(group: CourseReviewGroup, revision: number, previewOnly: boolean): Promise<void> {
    const courses = group.courses.filter(course => !course.reviewsLoaded)
    let next: number = 0
    let failed: boolean = false
    // Two groups are scheduled by the viewport loader. Two course readers per
    // group bound the fallback at four requests, without a directory-wide fan-out.
    const reader = async (): Promise<void> => {
      while (!failed && next < courses.length) {
        const course = courses[next++]
        try {
          CourseReviewRepository.guard(revision)
          const response = await ForumNetwork.getInstance().get(Constant.DANKE_BASE_URL + '/courses/' + course.id + '/reviews',
            undefined, undefined, 15000, !previewOnly)
          CourseReviewRepository.guard(revision)
          course.reviews = CourseReviewRepository.parseReviews(response.data); course.reviewsLoaded = true
        } catch (e) { failed = true; throw e as Error }
      }
    }
    await Promise.all([reader(), reader()])
  }
  static async add(draft: CourseReviewDraft): Promise<CourseReview> {
    if (!draft.valid()) throw new Error(AppLanguage.text($r('app.string.utility_invalid_review')))
    const revision = await CourseReviewRepository.session()
    const response = await ForumNetwork.getInstance().post(Constant.DANKE_BASE_URL + '/courses/' + draft.courseId + '/reviews', JSON.stringify(draft.body()))
    CourseReviewRepository.guard(revision)
    CourseReviewRepository.invalidateDetails()
    return CourseReviewRepository.parseReview(CourseReviewRepository.object(response.data))
  }
  static async modify(review: CourseReview, draft: CourseReviewDraft): Promise<void> {
    CourseReviewRepository.requireOwn(review)
    if (!draft.valid() || draft.courseId !== review.courseId) throw new Error(AppLanguage.text($r('app.string.utility_invalid_review')))
    const revision = await CourseReviewRepository.session()
    await ForumNetwork.getInstance().patch(Constant.DANKE_BASE_URL + '/reviews/' + review.id + '/_webvpn', JSON.stringify(draft.body()))
    CourseReviewRepository.guard(revision)
    CourseReviewRepository.invalidateDetails()
  }
  static async remove(review: CourseReview): Promise<void> {
    CourseReviewRepository.requireOwn(review)
    const revision = await CourseReviewRepository.session()
    await ForumNetwork.getInstance().delete(Constant.DANKE_BASE_URL + '/reviews/' + review.id)
    CourseReviewRepository.guard(revision)
    CourseReviewRepository.invalidateDetails()
  }
  static async vote(id: number, up: boolean): Promise<CourseReview> {
    CourseReviewRepository.requireId(id)
    const revision = await CourseReviewRepository.session()
    const body = new ReviewVoteBody(); body.upvote = up
    const response = await ForumNetwork.getInstance().patch(Constant.DANKE_BASE_URL + '/reviews/' + id, JSON.stringify(body))
    CourseReviewRepository.guard(revision)
    return CourseReviewRepository.parseReview(CourseReviewRepository.object(response.data))
  }
  private static async session(): Promise<number> {
    const forum = ForumRepository.getInstance()
    const revision = forum.sessionRevision(); const hadSession = forum.isLoggedIn()
    if (!await forum.restoreSession() || !forum.isLoggedIn()) throw new HttpError(401, 0, AppLanguage.text($r('app.string.utility_forum_login_hint')), '')
    if (hadSession && revision !== forum.sessionRevision()) throw new Error(AppLanguage.text($r('app.string.utility_account_changed')))
    return forum.sessionRevision()
  }
  private static guard(revision: number): void {
    const forum = ForumRepository.getInstance()
    if (!forum.isLoggedIn() || forum.sessionRevision() !== revision) throw new Error(AppLanguage.text($r('app.string.utility_account_changed')))
  }
  private static requireOwn(review: CourseReview): void {
    CourseReviewRepository.requireId(review.id)
    if (!review.isMe || review.deleted) throw new Error(AppLanguage.text($r('app.string.utility_review_owned_only')))
  }
  private static requireId(id: number): void { if (!Number.isSafeInteger(id) || id <= 0) throw new Error(AppLanguage.text($r('app.string.utility_invalid_identifier'))) }
  static parseSearch(body: string): CourseReviewSearch {
    const raw = CourseReviewRepository.object(body)
    if (!Array.isArray(raw['items'])) throw new HttpError(200, 0, AppLanguage.text($r('app.string.utility_invalid_response')), '')
    const result = new CourseReviewSearch()
    result.page = CourseReviewRepository.integer(raw['page']) || 1
    result.pageSize = CourseReviewRepository.integer(raw['page_size']) || CourseReviewRepository.SIZE
    result.extra = CourseReviewRepository.text(raw['extra'])
    result.items = (raw['items'] as Object[]).map(item => CourseReviewRepository.parseGroup(CourseReviewRepository.record(item), false))
    return result
  }
  static parseGroup(raw: Record<string, Object>, detailed: boolean): CourseReviewGroup {
    const group = new CourseReviewGroup()
    group.id = CourseReviewRepository.integer(raw['id']); group.name = CourseReviewRepository.text(raw['name'])
    if (group.id <= 0 || !group.name) throw new HttpError(200, 0, AppLanguage.text($r('app.string.utility_invalid_response')), '')
    group.code = CourseReviewRepository.text(raw['code']); group.department = CourseReviewRepository.text(raw['department'])
    group.campus = CourseReviewRepository.text(raw['campusName'] ?? raw['campus_name'] ?? raw['campus'])
    if (typeof raw['week_hour'] === 'number') group.weekHour = raw['week_hour'] as number
    if (typeof raw['course_count'] === 'number' && Number.isSafeInteger(raw['course_count']) && (raw['course_count'] as number) >= 0) group.courseCount = raw['course_count'] as number
    if (typeof raw['review_count'] === 'number' && Number.isSafeInteger(raw['review_count']) && (raw['review_count'] as number) >= 0) group.reviewCount = raw['review_count'] as number
    if (Array.isArray(raw['credits'])) group.credits = (raw['credits'] as Object[]).filter(item => typeof item === 'number').map(item => item as number)
    const courses: Object | undefined = raw['course_list'] ?? raw['courseList']
    if (detailed && !Array.isArray(courses)) throw new HttpError(200, 0, AppLanguage.text($r('app.string.utility_invalid_response')), '')
    if (Array.isArray(courses)) {
      group.courses = (courses as Object[]).map(item => CourseReviewRepository.parseCourse(CourseReviewRepository.record(item)))
      if (group.courseCount === undefined) group.courseCount = group.courses.length
      if (group.courses.length === 0 && group.reviewCount === undefined) group.reviewCount = 0
      CourseReviewRepository.attachReviewContext(group)
    }
    group.summary = CourseReviewSummary.from(group)
    return group
  }
  private static attachReviewContext(group: CourseReviewGroup): void {
    for (const course of group.courses) for (const review of course.reviews) {
      review.groupId = group.id; review.courseName = group.name; review.courseCode = group.code; review.department = group.department
      review.credit = course.credit; review.courseId = course.id; review.teacher = course.teacher; review.term = course.term
      review.campus = course.campus || group.campus
    }
  }
  static parseReviews(body: string): CourseReview[] {
    const parsed = JSON.parse(body) as Object
    if (!Array.isArray(parsed)) throw new HttpError(200, 0, AppLanguage.text($r('app.string.utility_invalid_response')), '')
    return (parsed as Object[]).map(item => CourseReviewRepository.parseReview(CourseReviewRepository.record(item)))
  }
  private static parseCourse(raw: Record<string, Object>): ReviewCourse {
    const result = new ReviewCourse(); result.id = CourseReviewRepository.integer(raw['id'])
    if (result.id <= 0) throw new HttpError(200, 0, AppLanguage.text($r('app.string.utility_invalid_response')), '')
    result.name = CourseReviewRepository.text(raw['name']); result.teacher = CourseReviewRepository.text(raw['teachers'])
    result.code = CourseReviewRepository.text(raw['code']); result.department = CourseReviewRepository.text(raw['department'])
    result.campus = CourseReviewRepository.text(raw['campusName'] ?? raw['campus_name'] ?? raw['campus'])
    result.year = CourseReviewRepository.integer(raw['year']); result.semester = CourseReviewRepository.integer(raw['semester'])
    if (typeof raw['credit'] === 'number' && Number.isFinite(raw['credit'] as number) && (raw['credit'] as number) >= 0) result.credit = raw['credit'] as number
    // Keep semester identity numeric here; the UI composes the translated term label.
    result.term = result.year > 0 ? String(result.year) + '–' + String(result.year + 1) + '/' + String(result.semester) : ''
    const reviews: Object | undefined = raw['review_list'] ?? raw['reviewList']
    if (Array.isArray(reviews)) {
      result.reviews = (reviews as Object[]).map(item => CourseReviewRepository.parseReview(CourseReviewRepository.record(item)))
      result.reviewsLoaded = true
    }
    return result
  }
  static parseReview(raw: Record<string, Object>): CourseReview {
    const review = new CourseReview(); review.id = CourseReviewRepository.integer(raw['id'])
    if (review.id <= 0) throw new HttpError(200, 0, AppLanguage.text($r('app.string.utility_invalid_response')), '')
    review.reviewerId = CourseReviewRepository.integer(raw['reviewer_id'])
    review.title = CourseReviewRepository.text(raw['title']); review.content = CourseReviewRepository.text(raw['content'])
    review.created = CourseReviewRepository.text(raw['timeCreated']); review.updated = CourseReviewRepository.text(raw['timeUpdated'])
    if (raw['rank'] !== undefined && raw['rank'] !== null) review.rank = ReviewRating.fromRaw(CourseReviewRepository.record(raw['rank']))
    review.votes = CourseReviewRepository.integer(raw['remark']); review.myVote = CourseReviewRepository.integer(raw['vote'])
    review.isMe = raw['is_me'] === true; review.deleted = raw['deleted'] === true
    review.modified = CourseReviewRepository.integer(raw['modified']); review.groupId = CourseReviewRepository.integer(raw['group_id'])
    const extra = raw['extra']
    if (extra !== null && typeof extra === 'object' && !Array.isArray(extra)) {
      const badges = (extra as Record<string, Object>)['achievements']
      if (Array.isArray(badges)) for (const badge of badges as Object[]) {
        if (badge === null || typeof badge !== 'object' || Array.isArray(badge)) continue
        const name = CourseReviewRepository.text((badge as Record<string, Object>)['name']).trim()
        if (name && !review.achievements.includes(name)) review.achievements.push(name)
      }
    }
    if (raw['course'] !== undefined && raw['course'] !== null) {
      const course = CourseReviewRepository.parseCourse(CourseReviewRepository.record(raw['course']))
      review.courseId = course.id; review.courseName = course.name; review.teacher = course.teacher; review.term = course.term
      review.courseCode = course.code; review.department = course.department; review.credit = course.credit
      review.campus = course.campus
    }
    return review
  }
  private static object(body: string): Record<string, Object> {
    let parsed: Object
    try { parsed = JSON.parse(body) as Object } catch (e) { throw new HttpError(200, 0, AppLanguage.text($r('app.string.utility_invalid_response')), '') }
    return CourseReviewRepository.record(parsed)
  }
  private static record(value: Object): Record<string, Object> {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new HttpError(200, 0, AppLanguage.text($r('app.string.utility_invalid_response')), '')
    return value as Record<string, Object>
  }
  private static integer(value: Object | undefined): number { return typeof value === 'number' && Number.isSafeInteger(value) ? value : 0 }
  private static text(value: Object | undefined): string { return typeof value === 'string' ? value : '' }
}
