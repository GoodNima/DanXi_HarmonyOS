import { ErrorDiagnostics } from '../model/ErrorDiagnostics'
/**
 * Forum (树洞) repository — real HTTP against fduhole.com.
 *
 * Replaces the previous hardcoded mock lists. Endpoint shapes and paging
 * parameters are taken from the upstream Flutter client; the extracted
 * contract is written up in danxi-forum-api-contract.md at the workspace root.
 *
 * Two hosts are involved:
 *   https://auth.fduhole.com/api   → /login, /refresh   (returns {access, refresh})
 *   https://forum.fduhole.com/api  → everything else    (needs Authorization: Bearer <access>)
 *
 * Note the two different paging keys the backend actually uses: `size` on
 * /holes/_homepage but `length` on /holes, and `offset`/`size` on /holes/{id}/floors.
 * They are not interchangeable — the upstream client sends exactly these.
 */

import { HttpUtil, HttpError, HttpResponse } from '../util/HttpUtil'
import { Constant } from '../common/Constant'
import { PreferencesUtil } from '../util/PreferencesUtil'
import { ForumImageUpload } from '../util/ForumImageUpload'
import { ForumPresentation } from '../common/ForumPresentation'
import { ForumNetwork } from '../common/ForumNetwork'
import { ForumRoute } from '../common/ForumRoute'
import { ForumPageRepository } from '../common/ForumPageRepository'
import { ForumPreferences } from '../common/ForumPreferences'
import { ForumHistory, ForumSummary } from '../model/ForumDetail'
import { ForumMessage } from '../model/ForumMessage'
import {
  ForumHole,
  ForumFloor,
  ForumTag,
  ForumDivision,
  ForumUser,
  ForumToken,
  TagBody,
  parseObject,
  parseObjectArray,
  jsonObject,
  jsonArray,
  jsonNumber,
} from '../model/Forum'

/** Request body for POST /login (forum_repository.dart:266-268) and /register. */
class LoginBody {
  email: string = ''
  password: string = ''
}

/** Request body for POST /divisions/{id}/holes (forum_repository.dart:558-574). */
class CreateHoleBody {
  content: string = ''
  tags: TagBody[] = []
}

/** Request body for POST /holes/{id}/floors (forum_repository.dart:597-609). */
class CreateFloorBody {
  content: string = ''
}

/**
 * Request body for the favourites/subscriptions mutations. Both directions of
 * both resources take the hole id in the body, not in the path
 * (forum_repository.dart:797-845).
 */
class HoleIdBody {
  hole_id: number = 0
}

class ReportBody { floor_id: number = 0; reason: string = '' }
class FeedbackBody { hole_id: number = 0; feedback_type: string = ''; reason?: string }
class HoleTagsBody { division_id: number = 0; tags: TagBody[] = [] }
class PinnedBody { pinned: number[] = [] }
class MessageReadBody { has_read: boolean = true }
class MessageClearBody { clear_all: boolean = true }

/** Only public division metadata is retained; pinned post contents are never persisted here. */
class CachedDivisionBody {
  division_id: number = 0
  name: string = ''
  description: string = ''
}

/** Bind the cache atomically to the existing credential entry, never to an unscoped second key. */
class CachedForumSession extends ForumToken {
  user_id: number = 0
  division_cache_version: number = 1
  division_cache: CachedDivisionBody[] = []
}

/** Sort orders accepted by the list endpoints (settings_provider.dart:916-925). */
export class ForumOrder {
  static readonly BY_TIME_UPDATED: string = 'time_updated'
  static readonly BY_TIME_CREATED: string = 'time_created'
}

export class ForumRepository implements ForumPageRepository {
  static readonly KEY_SESSION_REVISION: string = 'forum_session_revision'
  private static readonly DIVISIONS_FRESH_MS: number = 15 * 60 * 1000
  private static readonly DIVISIONS_RETRY_MS: number = 2 * 60 * 1000
  private static instance: ForumRepository | null = null
  private http: HttpUtil = HttpUtil.getInstance()
  private network: ForumNetwork = ForumNetwork.getInstance()
  private accessToken: string = ''
  private refreshToken: string = ''
  private sessionLoaded: boolean = false
  private refreshing: Promise<boolean> | null = null
  private preferenceRevision: number = 0
  private sessionGeneration: number = 0
  private authGeneration: number = 0
  private restoring: Promise<boolean> | null = null
  private divisionsRequest: Promise<ForumDivision[]> | null = null
  private divisionCache: ForumDivision[] = []
  private divisionsCheckedAt: number = 0
  private divisionsFailureAt: number = 0
  private divisionsFailure: Error | null = null
  private divisionsRevision: number = 0
  private sessionWrites: Promise<void> = Promise.resolve()
  private preferenceWrites: Promise<void> = Promise.resolve()

  private constructor() {
    // Route tokens by host: the forum token must never be sent to a UIS
    // endpoint, and /login must not carry a stale Authorization header.
    this.http.setTokenProvider((url: string): string => this.tokenForUrl(url))
    this.http.setUnauthorizedHandler((): Promise<boolean> => this.refresh())
  }

  static getInstance(): ForumRepository {
    if (!ForumRepository.instance) {
      ForumRepository.instance = new ForumRepository()
    }
    return ForumRepository.instance
  }

  private tokenForUrl(url: string): string {
    const original = ForumRoute.directUrl(url)
    if (original.indexOf(Constant.AUTH_BASE_URL) === 0) return ''
    if (this.isApiAddress(original, Constant.FORUM_BASE_URL) || this.isApiAddress(original, Constant.DANKE_BASE_URL)) return this.accessToken
    return ''
  }

  /** A first-party API path is a boundary, never a prefix for a different host or /apix. */
  private isApiAddress(address: string, base: string): boolean {
    if (!address.startsWith(base)) return false
    const boundary: string = address.charAt(base.length)
    return boundary === '' || boundary === '/' || boundary === '?' || boundary === '#'
  }

  private base(): string {
    return Constant.FORUM_BASE_URL
  }

  private authBase(): string {
    return Constant.AUTH_BASE_URL
  }

  // ───────────────────────────── authentication ─────────────────────────────

  /** Restore the persisted JWT pair. Safe to call repeatedly. */
  async restoreSession(): Promise<boolean> {
    if (this.sessionLoaded) { this.publishSession(); return this.isLoggedIn() }
    if (this.restoring !== null) return this.restoring
    const pending: Promise<boolean> = this.restoreSessionOnce(this.authGeneration)
    this.restoring = pending
    try {
      return await pending
    } finally {
      if (this.restoring === pending) this.restoring = null
    }
  }

  private async restoreSessionOnce(authGeneration: number): Promise<boolean> {
    const stored: string = await PreferencesUtil.getInstance().getString(Constant.KEY_FORUM_TOKEN, '')
    if (authGeneration !== this.authGeneration) return this.isLoggedIn()
    this.sessionLoaded = true
    if (!stored) { this.publishSession(0); return false }
    try {
      const entry: Record<string, Object> = parseObject(stored)
      const token = ForumToken.fromJson(entry)
      if (!token.isValid()) { this.publishSession(0); return false }
      this.accessToken = token.access
      this.refreshToken = token.refresh
      this.sessionGeneration++
      this.preferenceRevision++
      this.divisionCache = this.restoreDivisionCache(entry)
      this.invalidateDivisions()
      this.publishSession(jsonNumber(entry, 'user_id'))
      return true
    } catch (e) {
      // Corrupt entry: treat as signed out rather than crashing at startup.
      this.publishSession(0)
      return false
    }
  }

  isLoggedIn(): boolean {
    return this.accessToken.length > 0
  }

  /** Account/process scope for in-memory content caches; token refresh retains the same scope. */
  sessionRevision(): number { return this.sessionGeneration }

  /** The upstream placeholder is allowed only on first-party HTTPS forum/auth links. */
  resolveActivityAction(action: string): string {
    const placeholder: string = '{danta_access_token}'
    if (!action.includes(placeholder)) return action
    this.requireLogin()
    if (!/^https:\/\/(?:auth|forum)\.fduhole\.com(?:[/?#]|$)/i.test(action)) {
      throw new Error('该活动链接不支持安全验证')
    }
    return action.split(placeholder).join(encodeURIComponent(this.accessToken))
  }

  /** Publish ID before status/revision so every mounted account view sees one session. */
  private publishSession(userId: number = -1): void {
    if (userId >= 0 || !this.isLoggedIn()) {
      AppStorage.setOrCreate<number>(ForumPreferences.USER_ID, this.isLoggedIn() ? Math.max(0, userId) : 0)
    }
    AppStorage.setOrCreate<boolean>(Constant.KEY_FORUM_LOGGED_IN, this.isLoggedIn())
    AppStorage.setOrCreate<number>(ForumRepository.KEY_SESSION_REVISION, this.sessionGeneration)
  }

  peekCachedDivisions(): ForumDivision[] {
    return this.isLoggedIn() ? this.cloneDivisions(this.divisionCache) : []
  }

  private invalidateDivisions(): void {
    this.divisionsRevision++
    this.divisionsCheckedAt = 0
    this.divisionsFailureAt = 0
    this.divisionsFailure = null
    this.divisionsRequest = null
  }

  private cloneDivisions(divisions: ForumDivision[]): ForumDivision[] {
    const out: ForumDivision[] = []
    for (const division of divisions) {
      const copy = new ForumDivision()
      copy.divisionId = division.divisionId
      copy.name = division.name.slice(0, 128)
      copy.description = division.description.slice(0, 2048)
      copy.pinned = division.pinned.slice()
      out.push(copy)
    }
    return out
  }

  private restoreDivisionCache(entry: Record<string, Object>): ForumDivision[] {
    const out: ForumDivision[] = []
    if (jsonNumber(entry, 'division_cache_version') !== 1) return out
    for (const item of jsonArray(entry, 'division_cache')) {
      if (out.length >= 64) break
      if (item === null || typeof item !== 'object' || Array.isArray(item)) continue
      const division = ForumDivision.fromJson(item as Record<string, Object>)
      if (!Number.isInteger(division.divisionId) || division.divisionId <= 0 || division.name.trim().length === 0 ||
        out.some((row: ForumDivision): boolean => row.divisionId === division.divisionId)) continue
      division.name = division.name.slice(0, 128)
      division.description = division.description.slice(0, 2048)
      division.pinned = []
      out.push(division)
    }
    return out
  }

  private persistSession(generation: number): Promise<void> {
    // Serialize cache saves with refresh/login/logout. A late cache save must not
    // resurrect a logged-out token or replace a newer account/refresh pair.
    const pending: Promise<void> = this.sessionWrites.catch(() => {}).then(async (): Promise<void> => {
      if (generation !== this.sessionGeneration) return
      if (!this.isLoggedIn()) {
        await PreferencesUtil.getInstance().remove(Constant.KEY_FORUM_TOKEN)
        return
      }
      const stored = new CachedForumSession()
      stored.access = this.accessToken
      stored.refresh = this.refreshToken
      stored.user_id = AppStorage.get<number>(ForumPreferences.USER_ID) ?? 0
      for (const division of this.divisionCache) {
        const row = new CachedDivisionBody()
        row.division_id = division.divisionId
        row.name = division.name
        row.description = division.description
        stored.division_cache.push(row)
      }
      await PreferencesUtil.getInstance().putString(Constant.KEY_FORUM_TOKEN, JSON.stringify(stored))
    })
    this.sessionWrites = pending
    return pending
  }

  /**
   * Sign in to the tree hole with a forum account (NOT the Fudan UIS account —
   * fduhole accounts are separate). POST auth.fduhole.com/api/login.
   */
  async login(email: string, password: string): Promise<void> {
    const authGeneration: number = ++this.authGeneration
    const body = new LoginBody()
    body.email = email
    body.password = password

    const response: HttpResponse = await this.network.post(this.authBase() + '/login', JSON.stringify(body))
    const token = ForumToken.fromJson(parseObject(response.data))
    if (!token.isValid()) {
      // Upstream throws BadTokenException here (jwt.dart:31-37).
      throw new Error('登录失败：服务器未返回有效的凭证')
    }
    if (authGeneration !== this.authGeneration) throw new Error('登录操作已取消')
    this.accessToken = token.access
    this.refreshToken = token.refresh
    this.sessionLoaded = true
    this.sessionGeneration++
    this.preferenceRevision++
    this.divisionCache = []
    this.invalidateDivisions()
    this.refreshing = null
    const generation: number = this.sessionGeneration
    this.publishSession(0)
    await this.persistSession(this.sessionGeneration)
    if (generation !== this.sessionGeneration) throw new Error('登录操作已取消')
  }

  /**
   * Exchange the refresh token for a new pair. Called automatically by HttpUtil
   * on any 401 (mirrors jwt_interceptor.dart:68-91).
   * Returns true when a usable new access token is in hand.
   */
  async refresh(): Promise<boolean> {
    if (this.refreshing !== null) return this.refreshing
    const pending: Promise<boolean> = this.refreshOnce()
    this.refreshing = pending
    try {
      return await pending
    } finally {
      if (this.refreshing === pending) this.refreshing = null
    }
  }

  private async refreshOnce(): Promise<boolean> {
    if (!this.refreshToken) return false
    const generation: number = this.sessionGeneration
    try {
      const headers: Record<string, string> = { 'Authorization': 'Bearer ' + this.refreshToken }
      const response: HttpResponse = await this.network.post(this.authBase() + '/refresh', undefined, headers)
      const token = ForumToken.fromJson(parseObject(response.data))
      if (!token.isValid()) return false
      if (generation !== this.sessionGeneration) return false
      this.accessToken = token.access
      this.refreshToken = token.refresh
      await this.persistSession(generation)
      return generation === this.sessionGeneration
    } catch (e) {
      // Upstream clears tokens only when /refresh explicitly rejects them.
      // DNS/timeouts, WebVPN expiry and server failures must preserve login.
      if (e instanceof HttpError && e.isUnauthorized()) {
        if (generation === this.sessionGeneration) await this.forgetSession()
        return false
      }
      throw e as Error
    }
  }

  async forgetSession(): Promise<void> {
    this.authGeneration++
    this.sessionGeneration++
    this.preferenceRevision++
    this.accessToken = ''
    this.refreshToken = ''
    this.sessionLoaded = true
    this.divisionCache = []
    this.invalidateDivisions()
    this.refreshing = null
    this.publishSession(0)
    await this.persistSession(this.sessionGeneration)
  }

  private requireLogin(): void {
    if (!this.isLoggedIn()) {
      throw new Error('尚未登录树洞账号')
    }
  }

  // ──────────────────────────────── reads ────────────────────────────────

  /** GET /users/me. Also carries the `has_answered_questions` gate. */
  async getMe(): Promise<ForumUser> {
    this.requireLogin()
    const revision: number = this.preferenceRevision
    const generation: number = this.sessionGeneration
    const response = await this.network.get(this.base() + '/users/me')
    const user = ForumUser.fromJson(parseObject(response.data))
    if (generation !== this.sessionGeneration) throw new Error('树洞账号已切换，请重试')
    if (revision === this.preferenceRevision) await this.saveFoldBehavior(user.showFolded, generation, revision)
    if (generation !== this.sessionGeneration) throw new Error('树洞账号已切换，请重试')
    this.publishSession(user.userId)
    await this.persistSession(generation)
    if (generation !== this.sessionGeneration) throw new Error('树洞账号已切换，请重试')
    return user
  }

  /** Exact upstream /users/me paths and their distinct pagination contracts. */
  async getMyHoles(time: number, size: number = Constant.POST_COUNT_PER_PAGE): Promise<ForumHole[]> {
    this.requireLogin()
    const params: Record<string, string> = { 'offset': new Date(time).toISOString(),
      'size': String(size), 'order': ForumOrder.BY_TIME_CREATED }
    return ForumHole.listFromJson((await this.network.get(this.base() + '/users/me/holes', params)).data)
  }

  async getMyReplies(offset: number = 0, size: number = Constant.POST_COUNT_PER_PAGE): Promise<ForumFloor[]> {
    this.requireLogin()
    const params: Record<string, string> = { 'offset': String(offset), 'size': String(size), 'sort': 'desc' }
    return ForumFloor.listFromJson(parseObjectArray((await this.network.get(this.base() + '/users/me/floors', params)).data))
  }

  async getPunishments(): Promise<Record<string, Object>[]> {
    this.requireLogin()
    return parseObjectArray((await this.network.get(this.base() + '/users/me/punishments')).data)
  }

  /** Upstream messages list uses not_read and start_time, without a size key. */
  async getMessages(unreadOnly: boolean, startTime: number): Promise<ForumMessage[]> {
    this.requireLogin()
    const generation: number = this.sessionGeneration
    const params: Record<string, string> = {}
    params['not_read'] = String(unreadOnly)
    params['start_time'] = new Date(startTime).toISOString()
    const response = await this.network.get(this.base() + '/messages', params)
    if (generation !== this.sessionGeneration) throw new Error('树洞账号已切换，请重试')
    return parseObjectArray(response.data).map((row: Record<string, Object>) => ForumMessage.fromJson(row))
  }

  /** Upstream marks a notification with DELETE + has_read, rather than a guessed PATCH. */
  async markMessageRead(messageId: number): Promise<void> {
    this.requireLogin()
    if (!Number.isSafeInteger(messageId) || messageId <= 0) throw new Error('消息编号无效')
    const generation: number = this.sessionGeneration
    await this.network.delete(this.base() + '/messages/' + messageId, JSON.stringify(new MessageReadBody()))
    if (generation !== this.sessionGeneration) throw new Error('树洞账号已切换，请重试')
  }

  async clearMessages(): Promise<void> {
    this.requireLogin()
    const generation: number = this.sessionGeneration
    await this.network.patch(this.base() + '/messages/_webvpn', JSON.stringify(new MessageClearBody()))
    if (generation !== this.sessionGeneration) throw new Error('树洞账号已切换，请重试')
  }

  private async saveFoldBehavior(mode: string, generation: number = this.sessionGeneration,
    revision: number = this.preferenceRevision): Promise<void> {
    const value = ForumPresentation.foldMode(mode)
    const pending: Promise<void> = this.preferenceWrites.catch(() => {}).then(async (): Promise<void> => {
      if (generation !== this.sessionGeneration || revision !== this.preferenceRevision) return
      await PreferencesUtil.getInstance().putString(Constant.KEY_FORUM_FOLD_BEHAVIOR, value)
      if (generation === this.sessionGeneration && revision === this.preferenceRevision) {
        AppStorage.setOrCreate<string>(Constant.KEY_FORUM_FOLD_BEHAVIOR, value)
      }
    })
    this.preferenceWrites = pending
    await pending
  }

  /** Update the original three notification categories, retaining unknown future keys. */
  async setNotificationType(type: string, enabled: boolean): Promise<ForumUser> {
    this.requireLogin()
    const generation: number = this.sessionGeneration
    if (!['mention', 'favorite', 'report'].includes(type)) throw new Error('未知通知类型')
    const current = await this.network.get(this.base() + '/users/me')
    if (generation !== this.sessionGeneration) throw new Error('树洞账号已切换，请重试')
    const profile = parseObject(current.data)
    const user = ForumUser.fromJson(profile)
    if (user.userId <= 0) throw new Error('无法读取树洞设置')
    const config: Record<string, Object> = jsonObject(profile, 'config') ?? {}
    const notify = user.notify.filter((key: string) => key !== type)
    if (enabled) notify.push(type)
    config['notify'] = notify
    profile['config'] = config
    const response = await this.network.patch(this.base() + '/users/' + user.userId + '/_webvpn', JSON.stringify(profile))
    if (generation !== this.sessionGeneration) throw new Error('树洞账号已切换，请重试')
    const updated = ForumUser.fromJson(parseObject(response.data))
    if (updated.notify.includes(type) !== enabled) throw new Error('服务器未保存通知设置，请重试')
    return updated
  }

  /** Same server-backed preference as upstream, preserving notify and other profile fields. */
  async setFoldBehavior(mode: string): Promise<void> {
    this.requireLogin()
    this.preferenceRevision++
    const revision: number = this.preferenceRevision
    const generation: number = this.sessionGeneration
    const current = await this.network.get(this.base() + '/users/me')
    if (generation !== this.sessionGeneration) throw new Error('树洞账号已切换，请重试')
    const profile = parseObject(current.data)
    const user = ForumUser.fromJson(profile)
    if (user.userId <= 0) throw new Error('无法读取树洞设置，请重试')
    const config: Record<string, Object> = jsonObject(profile, 'config') ?? {}
    config['show_folded'] = ForumPresentation.foldMode(mode)
    profile['config'] = config
    const response = await this.network.patch(this.base() + '/users/' + user.userId + '/_webvpn', JSON.stringify(profile))
    if (generation !== this.sessionGeneration) throw new Error('树洞账号已切换，请重试')
    const updated = ForumUser.fromJson(parseObject(response.data))
    if (updated.showFolded !== mode) throw new Error('服务器未保存该设置，请重试')
    await this.saveFoldBehavior(updated.showFolded, generation, revision)
  }

  /**
   * GET /holes/_homepage — the main feed.
   * `offset` is an ISO-8601 UTC timestamp, not a page number.
   */
  async getHomepageHoles(startTimeMs: number, size: number = Constant.POST_COUNT_PER_PAGE,
    order: string = ForumOrder.BY_TIME_UPDATED): Promise<ForumHole[]> {
    this.requireLogin()
    const params: Record<string, string> = {
      'offset': new Date(startTimeMs).toISOString(),
      'size': String(size),
      'order': order,
    }
    const response = await this.network.get(this.base() + '/holes/_homepage', params)
    return ForumHole.listFromJson(response.data)
  }

  /**
   * GET /holes — the hole list for one division (or all).
   * NOTE: `/divisions/{id}/holes` is POST-only (it CREATES a hole); this GET is
   * the correct read path, and it pages with `length`, not `size`.
   */
  async getDivisionHoles(startTimeMs: number, divisionId: number, tag: string,
    length: number = Constant.POST_COUNT_PER_PAGE,
    order: string = ForumOrder.BY_TIME_UPDATED): Promise<ForumHole[]> {
    this.requireLogin()
    const params: Record<string, string> = {
      'start_time': new Date(startTimeMs).toISOString(),
      'length': String(length),
      'order': order,
    }
    if (divisionId > 0) params['division_id'] = String(divisionId)
    if (tag.length > 0) params['tag'] = tag
    const response = await this.network.get(this.base() + '/holes', params)
    return ForumHole.listFromJson(response.data)
  }

  /** Reuse current-session metadata; stale reads update behind the existing chips. */
  async getDivisions(force: boolean = false): Promise<ForumDivision[]> {
    this.requireLogin()
    const now: number = Date.now()
    const age: number = now - this.divisionsCheckedAt
    if (!force && this.divisionsCheckedAt > 0 && age >= 0 && age < ForumRepository.DIVISIONS_FRESH_MS) {
      return this.cloneDivisions(this.divisionCache)
    }
    const failureAge: number = now - this.divisionsFailureAt
    if (!force && this.divisionsFailure !== null && failureAge >= 0 && failureAge < ForumRepository.DIVISIONS_RETRY_MS) {
      if (this.divisionCache.length > 0) return this.cloneDivisions(this.divisionCache)
      throw this.divisionsFailure
    }
    const generation: number = this.sessionGeneration
    const revision: number = this.divisionsRevision
    const pending: Promise<ForumDivision[]> = this.divisionsRequest !== null ? this.divisionsRequest :
      this.fetchDivisions(generation, revision)
    this.divisionsRequest = pending
    try {
      return this.cloneDivisions(await pending)
    } catch (e) {
      if (generation === this.sessionGeneration && revision === this.divisionsRevision && this.isLoggedIn()) {
        this.divisionsFailureAt = Date.now()
        this.divisionsFailure = e as Error
        if (!force && this.divisionCache.length > 0) return this.cloneDivisions(this.divisionCache)
      }
      throw e as Error
    } finally {
      if (this.divisionsRequest === pending) this.divisionsRequest = null
    }
  }

  private async fetchDivisions(generation: number, revision: number): Promise<ForumDivision[]> {
    const response = await this.network.get(this.base() + '/divisions')
    if (generation !== this.sessionGeneration || !this.isLoggedIn()) throw new Error('树洞账号已切换，请重试')
    if (revision !== this.divisionsRevision) throw new Error('分区资料已更新，请重试')
    if (!Array.isArray(JSON.parse(response.data))) throw new Error('服务器返回了非预期的分区格式')
    const out: ForumDivision[] = []
    for (const item of parseObjectArray(response.data)) {
      const division = ForumDivision.fromJson(item)
      if (Number.isInteger(division.divisionId) && division.divisionId > 0 && division.name.trim().length > 0 &&
        !out.some((row: ForumDivision): boolean => row.divisionId === division.divisionId)) out.push(division)
    }
    this.divisionCache = this.cloneDivisions(out.slice(0, 64))
    this.divisionsCheckedAt = Date.now()
    this.divisionsFailureAt = 0
    this.divisionsFailure = null
    this.persistSession(generation).catch((e: Object) => {
      console.warn('DanXi: division cache could not be saved: ' + ForumRepository.describeError(e))
    })
    return out
  }

  /** GET /holes/{id} — a single hole. */
  async getHole(holeId: number): Promise<ForumHole> {
    this.requireLogin()
    const response = await this.network.get(this.base() + '/holes/' + holeId)
    return ForumHole.fromJson(parseObject(response.data))
  }

  /** GET /floors/{id} — resolve a quote, matching upstream loadFloorById. */
  async getFloor(floorId: number): Promise<ForumFloor> {
    this.requireLogin()
    const response = await this.network.get(this.base() + '/floors/' + floorId)
    return ForumFloor.fromJson(parseObject(response.data))
  }

  /** GET /holes/{id}/floors — paged floors. No sort parameter exists. */
  async getFloors(holeId: number, offset: number, size: number = Constant.POST_COUNT_PER_PAGE): Promise<ForumFloor[]> {
    this.requireLogin()
    const params: Record<string, string> = { 'offset': String(offset), 'size': String(size) }
    const response = await this.network.get(this.base() + '/holes/' + holeId + '/floors', params)
    const out: ForumFloor[] = []
    for (const item of parseObjectArray(response.data)) {
      out.push(ForumFloor.fromJson(item))
    }
    return out
  }

  /** GET /tags. */
  async getTags(): Promise<ForumTag[]> {
    this.requireLogin()
    const response = await this.network.get(this.base() + '/tags')
    const out: ForumTag[] = []
    const seen: Set<string> = new Set<string>()
    for (const item of parseObjectArray(response.data)) {
      const tag = ForumTag.fromJson(item)
      const key = String(tag.tagId) + ':' + tag.name
      if (tag.name.length > 0 && !seen.has(key)) {
        seen.add(key)
        out.push(tag)
      }
    }
    return out
  }

  /**
   * GET /floors/search.
   * Unlike the list endpoints, the date bounds here are integer EPOCH SECONDS.
   */
  async searchFloors(keyword: string, offset: number = 0, size: number = Constant.POST_COUNT_PER_PAGE,
    accurate: boolean = false): Promise<ForumFloor[]> {
    this.requireLogin()
    const params: Record<string, string> = {
      'offset': String(offset),
      'search': keyword,
      'size': String(size),
      'accurate': accurate ? 'true' : 'false',
    }
    const response = await this.network.get(this.base() + '/floors/search', params)
    const out: ForumFloor[] = []
    for (const item of parseObjectArray(response.data)) {
      out.push(ForumFloor.fromJson(item))
    }
    return out
  }

  // ──────────────────────────────── writes ────────────────────────────────

  /**
   * POST /divisions/{divisionId}/holes.
   * The body is exactly {content, tags}; when no tag is chosen the upstream
   * client sends the sentinel tag {0, 0, "默认"} (forum_repository.dart:561).
   */
  async createHole(divisionId: number, content: string, tags: ForumTag[]): Promise<void> {
    this.requireLogin()
    const body = new CreateHoleBody()
    body.content = content
    if (tags.length > 0) {
      for (const tag of tags) body.tags.push(tag.toBody())
    } else {
      const fallback = new TagBody()
      fallback.tag_id = 0
      fallback.temperature = 0
      fallback.name = '默认'
      body.tags.push(fallback)
    }
    await this.network.post(this.base() + '/divisions/' + divisionId + '/holes', JSON.stringify(body))
  }

  /** Upload one selected image without replaying a write after authentication errors. */
  async uploadImage(filePath: string, filename: string): Promise<string> {
    this.requireLogin()
    return await ForumImageUpload.upload(filePath, filename, this.accessToken)
  }

  /**
   * POST /holes/{holeId}/floors.
   * There is no reply_to / is_anonymous field in the API. Replying to a specific
   * floor is expressed by seeding the content with "##<floorId>\n"
   * (hole_editor.dart:163); anonymity is assigned by the server.
   */
  async createFloor(holeId: number, content: string): Promise<void> {
    this.requireLogin()
    const body = new CreateFloorBody()
    body.content = content
    await this.network.post(this.base() + '/holes/' + holeId + '/floors', JSON.stringify(body))
  }

  /** Reply to a specific floor, using the upstream "##<floorId>" content prefix. */
  async replyToFloor(holeId: number, floorId: number, content: string): Promise<void> {
    await this.createFloor(holeId, '##' + floorId + '\n' + content)
  }

  /**
   * POST /floors/{floorId}/like/{like}.
   * `like` is 1 = like, 0 = cancel like, -1 = dislike, 0 = cancel dislike
   * (forum_widgets.dart:891,915-916). Returns the updated floor.
   */
  async likeFloor(floorId: number, like: number): Promise<ForumFloor> {
    this.requireLogin()
    const response = await this.network.post(this.base() + '/floors/' + floorId + '/like/' + like)
    return ForumFloor.fromJson(parseObject(response.data))
  }

  /** PATCH /holes/{id} with no body — the upstream view-count bump. */
  async markHoleRead(holeId: number): Promise<void> {
    this.requireLogin()
    await this.network.patch(this.base() + '/holes/' + holeId)
  }

  /** Upstream /_webvpn is part of the API path even for direct requests. */
  async modifyFloor(id: number, content: string): Promise<void> {
    this.requireLogin()
    const body = new CreateFloorBody(); body.content = content
    await this.network.patch(this.base() + '/floors/' + id + '/_webvpn', JSON.stringify(body))
  }

  async deleteFloor(id: number, reason?: string): Promise<void> {
    this.requireLogin()
    const body: Record<string, string> = {}
    if (reason?.trim()) body['delete_reason'] = reason.trim()
    await this.network.delete(this.base() + '/floors/' + id, reason === undefined ? undefined : JSON.stringify(body))
  }

  async reportFloor(id: number, reason: string): Promise<void> {
    this.requireLogin()
    if (!reason.trim()) throw new Error('举报原因不能为空')
    const body = new ReportBody(); body.floor_id = id; body.reason = reason.trim()
    await this.network.post(this.base() + '/reports', JSON.stringify(body))
  }

  async getHistory(id: number): Promise<ForumHistory[]> {
    this.requireLogin()
    const response = await this.network.get(this.base() + '/floors/' + id + '/history')
    return parseObjectArray(response.data).map((item: Record<string, Object>) => ForumHistory.fromJson(item))
  }

  async getSummary(id: number, refresh: boolean = false): Promise<ForumSummary> {
    this.requireLogin()
    const response = await this.network.get(this.base() + '/holes/' + id + '/summary', refresh ? { 'force_refresh': 'true' } : undefined)
    return ForumSummary.fromJson(parseObject(response.data))
  }

  async summaryFeedback(id: number, type: string, reason: string = ''): Promise<void> {
    this.requireLogin()
    if (!['upvote', 'downvote'].includes(type)) throw new Error('Invalid summary feedback')
    const body = new FeedbackBody(); body.hole_id = id; body.feedback_type = type
    if (reason.trim()) body.reason = reason.trim()
    await this.network.post(this.base() + '/holes/' + id + '/summary/feedback', JSON.stringify(body))
  }

  async moderateHole(id: number, action: string, enabled: boolean): Promise<void> {
    this.requireLogin()
    if (action === 'delete' || action === 'force') {
      await this.network.delete(this.base() + '/holes/' + id + (action === 'force' ? '/_force' : ''))
      return
    }
    if (!['lock', 'frozen', 'unhidden'].includes(action)) throw new Error('Unsupported moderation action')
    const body: Record<string, boolean> = {}; body[action] = enabled
    await this.network.patch(this.base() + '/holes/' + id + '/_webvpn', JSON.stringify(body))
  }

  async moderateFloor(id: number, action: string, value: string): Promise<void> {
    this.requireLogin()
    let path: string = '/floors/' + id + '/_webvpn'
    const body: Record<string, Object> = {}
    if (action === 'special_tag') body[action] = value
    else if (action === 'fold') body[action] = value.split('\n').map((item: string) => item.trim()).filter((item: string) => item.length > 0)
    else if (action === 'sensitive') { path = '/floors/' + id + '/_sensitive/_webvpn'; body['is_actual_sensitive'] = value === 'true' }
    else if (action === 'penalty') {
      const days: number = Number(value)
      if (!Number.isInteger(days) || days < 0) throw new Error('Invalid penalty days')
      await this.network.post(this.base() + '/penalty/' + id, JSON.stringify({ 'days': days } as Record<string, number>))
      return
    } else throw new Error('Unsupported moderation action')
    await this.network.patch(this.base() + path, JSON.stringify(body))
  }

  async updateHoleTags(id: number, division: number, tags: ForumTag[]): Promise<void> {
    this.requireLogin()
    const generation: number = this.sessionGeneration
    const body = new HoleTagsBody(); body.division_id = division
    body.tags = tags.map((tag: ForumTag) => tag.toBody())
    await this.network.patch(this.base() + '/holes/' + id + '/_webvpn', JSON.stringify(body))
    if (generation === this.sessionGeneration) this.invalidateDivisions()
  }

  async setPinned(division: number, holes: number[]): Promise<void> {
    this.requireLogin()
    const generation: number = this.sessionGeneration
    const body = new PinnedBody(); body.pinned = holes
    await this.network.patch(this.base() + '/divisions/' + division + '/_webvpn', JSON.stringify(body))
    if (generation === this.sessionGeneration) this.invalidateDivisions()
  }

  /**
   * Favourites and subscriptions are the only endpoints that wrap their id list
   * one level deeper than everything else: the payload is `{"data": [1,2,3]}`
   * rather than a bare array (forum_repository.dart:744, 763). Non-numeric
   * members are dropped instead of becoming NaN.
   */
  private static idListFromEnvelope(data: string): number[] {
    const envelope = parseObject(data)
    const inner: Object | undefined = envelope['data']
    const out: number[] = []
    if (Array.isArray(inner)) {
      for (const item of inner as Object[]) {
        if (typeof item === 'number') out.push(item as number)
      }
    }
    return out
  }

  /** GET /user/favorites?plain=true — the favourited hole ids, not the holes. */
  async getFavoriteHoleIds(): Promise<number[]> {
    this.requireLogin()
    const params: Record<string, string> = { 'plain': 'true' }
    const response = await this.network.get(this.base() + '/user/favorites', params)
    return ForumRepository.idListFromEnvelope(response.data)
  }

  /** iOS FavoritePage reads this ordered response, independently of feed sorting. */
  async getFavoriteHoles(): Promise<ForumHole[]> {
    this.requireLogin()
    const response = await this.network.get(this.base() + '/user/favorites')
    const values = JSON.parse(response.data) as Record<string, Object>[]
    if (!Array.isArray(values)) throw new Error('Favorite holes response is invalid')
    const known: Set<number> = new Set<number>()
    return values.map((row: Record<string, Object>): ForumHole => ForumHole.fromJson(row))
      .filter((hole: ForumHole): boolean => {
        if (hole.holeId <= 0 || known.has(hole.holeId)) return false
        known.add(hole.holeId)
        return true
      })
  }

  /** GET /users/subscriptions?plain=true — the subscribed hole ids. */
  async getSubscribedHoleIds(): Promise<number[]> {
    this.requireLogin()
    const params: Record<string, string> = { 'plain': 'true' }
    const response = await this.network.get(this.base() + '/users/subscriptions', params)
    return ForumRepository.idListFromEnvelope(response.data)
  }

  /**
   * Add or remove a favourite.
   *
   * Both directions live on `/user/favorites` and carry the hole id in the
   * BODY: POST {hole_id} adds, DELETE {hole_id} removes
   * (forum_repository.dart:797-820). There is no `/holes/{id}/favorite` route —
   * an earlier revision of this file invented one, which would have 404'd.
   */
  async setFavorite(holeId: number, favorite: boolean): Promise<void> {
    this.requireLogin()
    const body = new HoleIdBody()
    body.hole_id = holeId
    const url = this.base() + '/user/favorites'
    if (favorite) {
      await this.network.post(url, JSON.stringify(body))
    } else {
      await this.network.delete(url, JSON.stringify(body))
    }
  }

  /**
   * Subscribe or unsubscribe a hole. Same body-carries-the-id shape as
   * favourites, on `/users/subscriptions` (forum_repository.dart:822-845).
   */
  async setSubscription(holeId: number, subscribed: boolean): Promise<void> {
    this.requireLogin()
    const body = new HoleIdBody()
    body.hole_id = holeId
    const url = this.base() + '/users/subscriptions'
    if (subscribed) {
      await this.network.post(url, JSON.stringify(body))
    } else {
      await this.network.delete(url, JSON.stringify(body))
    }
  }

  /**
   * Turn a thrown error into something worth showing a user.
   * Prefers the server's own message over a generic status string.
   */
  static describeError(error: Object): string {
    if (error instanceof HttpError && error.isUnauthorized()) return ErrorDiagnostics.message(error, '登录已过期，请重新登录树洞账号')
    return ErrorDiagnostics.message(error)

  }
}

/** Re-exported so pages can reference the nested-object helper without another import. */
export { jsonObject }
