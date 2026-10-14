/**
 * Base repository - provides common HTTP operations.
 * Ported from lib/repository/base_repository.dart
 */

import { HttpUtil, HttpResponse } from '../util/HttpUtil'

export class BaseRepository {
  protected httpUtil: HttpUtil

  constructor() {
    this.httpUtil = HttpUtil.getInstance()
  }

  protected async safeGet(url: string, params?: Record<string, string>): Promise<HttpResponse> {
    return this.httpUtil.get(url, params)
  }

  protected async safePost(url: string, body?: string): Promise<HttpResponse> {
    return this.httpUtil.post(url, body)
  }

  protected async safePut(url: string, body?: string): Promise<HttpResponse> {
    return this.httpUtil.put(url, body)
  }

  protected async safeDelete(url: string): Promise<HttpResponse> {
    return this.httpUtil.delete(url)
  }

  protected parseJson<T>(response: HttpResponse): T | null {
    if (!response.success || !response.data) return null
    try {
      return JSON.parse(response.data) as T
    } catch (e) {
      return null
    }
  }
}
