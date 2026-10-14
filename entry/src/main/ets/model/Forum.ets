/**
 * Forum (树洞) wire models for the fduhole.com API.
 *
 * Field-for-field with the server payload. Upstream proof that the Dart field
 * names ARE the JSON keys: every model in lib/model/forum/ uses a bare
 * `@JsonSerializable()` with no `@JsonKey(name:)` rename anywhere in that
 * directory, which is exactly why those files carry
 * `// ignore_for_file: non_constant_identifier_names`.
 *
 * Deliberate oddity: the server key is `anonyname` (lib/model/forum/floor.dart:31),
 * one 'n' in the middle. It is NOT a typo in this port.
 *
 * The API is loosely typed — any field may be missing or null — so every parse
 * coerces with a fallback instead of throwing.
 */

// ──────────────────────────── JSON coercion helpers ────────────────────────────

export function jsonString(source: Record<string, Object>, key: string, fallback: string = ''): string {
  const value: Object | undefined = source[key]
  return typeof value === 'string' ? value as string : fallback
}

export function jsonNumber(source: Record<string, Object>, key: string, fallback: number = 0): number {
  const value: Object | undefined = source[key]
  return typeof value === 'number' ? value as number : fallback
}

export function jsonBoolean(source: Record<string, Object>, key: string, fallback: boolean = false): boolean {
  const value: Object | undefined = source[key]
  return typeof value === 'boolean' ? value as boolean : fallback
}

export function jsonArray(source: Record<string, Object>, key: string): Object[] {
  const value: Object | undefined = source[key]
  return Array.isArray(value) ? value as Object[] : []
}

/** Returns the nested object at `key`, or null when absent / null / not an object. */
export function jsonObject(source: Record<string, Object>, key: string): Record<string, Object> | null {
  const value: Object | undefined = source[key]
  if (value === undefined || value === null) return null
  if (typeof value !== 'object') return null
  if (Array.isArray(value)) return null
  return value as Record<string, Object>
}

function isPlainObject(value: Object): boolean {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

/** JSON.parse that guarantees a top-level object. Throws on any other shape. */
export function parseObject(text: string): Record<string, Object> {
  const parsed = JSON.parse(text) as Object
  if (!isPlainObject(parsed)) {
    throw new Error('服务器返回了非预期的响应格式')
  }
  return parsed as Record<string, Object>
}

/** JSON.parse that guarantees a top-level object array. Non-objects are skipped. */
export function parseObjectArray(text: string): Record<string, Object>[] {
  const parsed = JSON.parse(text) as Object
  const out: Record<string, Object>[] = []
  if (!Array.isArray(parsed)) return out
  const items = parsed as Object[]
  for (const item of items) {
    if (isPlainObject(item)) out.push(item as Record<string, Object>)
  }
  return out
}

/**
 * Parse a `{code, message, data}` envelope.
 * Only /holes/{id}/summary uses this shape upstream (ai_summary.dart:24-44);
 * every other endpoint returns a bare object or array.
 */
export function parseEnvelope(text: string): Object | null {
  const parsed = parseObject(text)
  return parsed['data']
}

function pad2(value: number): string {
  return value < 10 ? '0' + value : String(value)
}

/**
 * Relative time for list rendering. Returns '' for unparseable input so the UI
 * degrades to showing nothing rather than "NaN分钟前".
 */
export function formatRelativeTime(iso: string): string {
  if (!iso || iso.length === 0) return ''
  const then = new Date(iso).getTime()
  if (Number.isNaN(then)) return ''
  const diffMin = Math.floor((Date.now() - then) / 60000)
  if (diffMin < 1) return '刚刚'
  if (diffMin < 60) return diffMin + '分钟前'
  const diffHour = Math.floor(diffMin / 60)
  if (diffHour < 24) return diffHour + '小时前'
  const diffDay = Math.floor(diffHour / 24)
  if (diffDay < 7) return diffDay + '天前'
  const date = new Date(then)
  return date.getFullYear() + '-' + pad2(date.getMonth() + 1) + '-' + pad2(date.getDate())
}

// ──────────────────────────────── Models ────────────────────────────────

/** OTTag — lib/model/forum/tag.dart:29-31 */
export class ForumTag {
  tagId: number = 0
  temperature: number = 0
  name: string = ''

  static fromJson(source: Record<string, Object>): ForumTag {
    const tag = new ForumTag()
    tag.tagId = jsonNumber(source, 'tag_id')
    tag.temperature = jsonNumber(source, 'temperature')
    tag.name = jsonString(source, 'name')
    return tag
  }

  /** Server-to-request shape. Wire keys are the Dart field names. */
  toBody(): TagBody {
    const body = new TagBody()
    body.tag_id = this.tagId
    body.temperature = this.temperature
    body.name = this.name
    return body
  }
}

/** Request body for POST /divisions/{id}/holes (forum_repository.dart:558-574). */
export class TagBody {
  tag_id: number = 0
  temperature: number = 0
  name: string = ''
}

/** OTFloor — lib/model/forum/floor.dart:28-43 */
export class ForumFloor {
  floorId: number = 0
  holeId: number = 0
  /** Backend ranking is one-based; zero means an older payload omitted it. */
  ranking: number = 0
  content: string = ''
  /** Server-assigned pseudonym. Wire key really is `anonyname`. */
  anonyname: string = ''
  timeCreated: string = ''
  timeUpdated: string = ''
  /** Admin-applied tag; read-only for normal users. */
  specialTag: string = ''
  deleted: boolean = false
  isMe: boolean = false
  liked: boolean = false
  fold: string[] = []
  modified: number = 0
  like: number = 0
  mention: ForumFloor[] = []
  dislike: number = 0
  disliked: boolean = false

  withVote(target: number): ForumFloor {
    const floor: ForumFloor = new ForumFloor()
    floor.floorId = this.floorId; floor.holeId = this.holeId; floor.ranking = this.ranking; floor.content = this.content
    floor.anonyname = this.anonyname; floor.timeCreated = this.timeCreated; floor.timeUpdated = this.timeUpdated
    floor.specialTag = this.specialTag; floor.deleted = this.deleted; floor.isMe = this.isMe
    floor.fold = this.fold.slice(); floor.modified = this.modified; floor.mention = this.mention
    floor.liked = target === 1; floor.disliked = target === -1
    floor.like = Math.max(0, this.like + (floor.liked ? 1 : 0) - (this.liked ? 1 : 0))
    floor.dislike = Math.max(0, this.dislike + (floor.disliked ? 1 : 0) - (this.disliked ? 1 : 0))
    return floor
  }

  static fromJson(source: Record<string, Object>): ForumFloor {
    const floor = new ForumFloor()
    floor.floorId = jsonNumber(source, 'floor_id')
    floor.holeId = jsonNumber(source, 'hole_id')
    const ranking: number = jsonNumber(source, 'ranking')
    floor.ranking = Number.isSafeInteger(ranking) && ranking > 0 ? ranking : 0
    floor.content = jsonString(source, 'content')
    floor.anonyname = jsonString(source, 'anonyname')
    floor.timeCreated = jsonString(source, 'time_created')
    floor.timeUpdated = jsonString(source, 'time_updated')
    floor.specialTag = jsonString(source, 'special_tag')
    floor.deleted = jsonBoolean(source, 'deleted')
    floor.isMe = jsonBoolean(source, 'is_me')
    floor.liked = jsonBoolean(source, 'liked')
    floor.modified = jsonNumber(source, 'modified')
    floor.like = jsonNumber(source, 'like')
    floor.dislike = jsonNumber(source, 'dislike')
    floor.disliked = jsonBoolean(source, 'disliked')
    floor.fold = jsonStringArray(source, 'fold')
    floor.mention = ForumFloor.listFromJson(jsonArray(source, 'mention'))
    return floor
  }

  static listFromJson(items: Object[]): ForumFloor[] {
    const out: ForumFloor[] = []
    for (const item of items) {
      if (isPlainObject(item)) out.push(ForumFloor.fromJson(item as Record<string, Object>))
    }
    return out
  }

  /** `fold` is a list of folded-reason strings, joined for display (floor.dart:128). */
  getFoldReason(): string {
    return this.fold.join(' ')
  }

  getDisplayTime(): string {
    return formatRelativeTime(this.timeUpdated.length > 0 ? this.timeUpdated : this.timeCreated)
  }
}

function jsonStringArray(source: Record<string, Object>, key: string): string[] {
  const out: string[] = []
  for (const item of jsonArray(source, key)) {
    if (typeof item === 'string') out.push(item as string)
  }
  return out
}

/** OTHole — lib/model/forum/hole.dart:28-42 */
export class ForumHole {
  holeId: number = 0
  divisionId: number = 0
  timeCreated: string = ''
  timeUpdated: string = ''
  /** Non-empty and date-parseable ⇒ the hole was force-deleted (hole.dart:66-69). */
  timeDeleted: string = ''
  tags: ForumTag[] = []
  view: number = 0
  reply: number = 0
  firstFloor: ForumFloor | null = null
  lastFloor: ForumFloor | null = null
  hidden: boolean = false
  locked: boolean = false
  frozen: boolean = false
  favoriteCount: number = 0
  subscriptionCount: number = 0
  aiSummaryAvailable: boolean = false

  static fromJson(source: Record<string, Object>): ForumHole {
    const hole = new ForumHole()
    hole.holeId = jsonNumber(source, 'hole_id')
    hole.divisionId = jsonNumber(source, 'division_id')
    hole.timeCreated = jsonString(source, 'time_created')
    hole.timeUpdated = jsonString(source, 'time_updated')
    hole.timeDeleted = jsonString(source, 'time_deleted')
    hole.view = jsonNumber(source, 'view')
    hole.reply = jsonNumber(source, 'reply')
    hole.hidden = jsonBoolean(source, 'hidden')
    hole.locked = jsonBoolean(source, 'locked')
    hole.frozen = jsonBoolean(source, 'frozen')
    hole.favoriteCount = jsonNumber(source, 'favorite_count')
    hole.subscriptionCount = jsonNumber(source, 'subscription_count')
    hole.aiSummaryAvailable = jsonBoolean(source, 'ai_summary_available')

    for (const item of jsonArray(source, 'tags')) {
      if (isPlainObject(item)) hole.tags.push(ForumTag.fromJson(item as Record<string, Object>))
    }

    const floors = jsonObject(source, 'floors')
    if (floors !== null) {
      const first = jsonObject(floors, 'first_floor')
      if (first !== null) hole.firstFloor = ForumFloor.fromJson(first)
      const last = jsonObject(floors, 'last_floor')
      if (last !== null) hole.lastFloor = ForumFloor.fromJson(last)
    }
    return hole
  }

  static listFromJson(text: string): ForumHole[] {
    const out: ForumHole[] = []
    for (const item of parseObjectArray(text)) {
      out.push(ForumHole.fromJson(item))
    }
    return out
  }

  /** Holes have no title — the list shows the opening post's content. */
  getPreview(maxLength: number = 100): string {
    const text: string = this.firstFloor !== null ? this.firstFloor.content : ''
    const flat: string = text.replace(/\s+/g, ' ').trim()
    if (flat.length <= maxLength) return flat
    return flat.substring(0, maxLength) + '…'
  }

  getAuthor(): string {
    return this.firstFloor !== null ? this.firstFloor.anonyname : ''
  }

  getDisplayTime(): string {
    return formatRelativeTime(this.timeUpdated.length > 0 ? this.timeUpdated : this.timeCreated)
  }

  isForceDeleted(): boolean {
    return this.timeDeleted.length > 0
  }
}

/** OTDivision — lib/model/forum/division.dart:40-43 */
export class ForumDivision {
  divisionId: number = 0
  name: string = ''
  description: string = ''
  pinned: ForumHole[] = []

  static fromJson(source: Record<string, Object>): ForumDivision {
    const division = new ForumDivision()
    division.divisionId = jsonNumber(source, 'division_id')
    division.name = jsonString(source, 'name')
    division.description = jsonString(source, 'description')
    for (const item of jsonArray(source, 'pinned')) {
      if (isPlainObject(item)) division.pinned.push(ForumHole.fromJson(item as Record<string, Object>))
    }
    return division
  }
}

/** OTUser — lib/model/forum/user.dart:28-36 */
export class ForumUser {
  notify: string[] = []
  showFolded: string = 'fold'
  userId: number = 0
  nickname: string = ''
  favorites: number[] = []
  subscriptions: number[] = []
  joinedTime: string = ''
  isAdmin: boolean = false
  /**
   * The upstream client refuses to load any forum content until this is true
   * (subpage_forum.dart:410-415). Reproduced here so behaviour matches.
   */
  hasAnsweredQuestions: boolean = false

  static fromJson(source: Record<string, Object>): ForumUser {
    const user = new ForumUser()
    user.userId = jsonNumber(source, 'user_id')
    user.nickname = jsonString(source, 'nickname')
    user.joinedTime = jsonString(source, 'joined_time')
    user.isAdmin = jsonBoolean(source, 'is_admin')
    user.hasAnsweredQuestions = jsonBoolean(source, 'has_answered_questions')
    user.favorites = jsonNumberArray(source, 'favorites')
    user.subscriptions = jsonNumberArray(source, 'subscriptions')
    const config = jsonObject(source, 'config')
    if (config !== null) {
      user.notify = jsonArray(config, 'notify').filter((item: Object) => typeof item === 'string') as string[]
      const mode = jsonString(config, 'show_folded')
      user.showFolded = mode === 'show' || mode === 'hide' ? mode : 'fold'
    }
    return user
  }
}

function jsonNumberArray(source: Record<string, Object>, key: string): number[] {
  const out: number[] = []
  for (const item of jsonArray(source, key)) {
    if (typeof item === 'number') out.push(item as number)
  }
  return out
}

/** JWToken — lib/model/forum/jwt.dart:22-24. The login response IS this object. */
export class ForumToken {
  access: string = ''
  refresh: string = ''

  static fromJson(source: Record<string, Object>): ForumToken {
    const token = new ForumToken()
    token.access = jsonString(source, 'access')
    token.refresh = jsonString(source, 'refresh')
    return token
  }

  isValid(): boolean {
    return this.access.length > 0 && this.refresh.length > 0
  }
}
