import { http } from '@kit.NetworkKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { url } from '@kit.ArkTS'
import { Constant } from '../common/Constant'
import { NetworkProxy } from '../common/NetworkProxy'

interface UploadedImage { display_url?: string; url?: string }
interface UploadResponse { image?: UploadedImage }

/** The upstream image service contract is POST /json, multipart field source. */
export class ForumImageUpload {
  static async upload(filePath: string, filename: string, token: string,
    isCurrent: () => boolean = (): boolean => true): Promise<string> {
    if (!ForumImageUpload.isLocalPath(filePath)) throw new Error('图片文件地址无效')
    if (!ForumImageUpload.isSafeFilename(filename)) throw new Error('图片文件名无效')
    if (!token || token.length > 8192 || !/^[A-Za-z0-9._~+\/-]+=*$/.test(token)) {
      throw new Error('请先登录茶楼后再上传图片')
    }
    if (!isCurrent()) throw new Error('茶楼账号已切换，已取消图片上传。')
    try {
      const file: fs.Stat = await fs.stat(filePath)
      if (!file.isFile() || file.size <= 0) throw new Error('invalid image file')
    } catch (e) {
      throw new Error('无法读取图片，请重新选择')
    }
    if (!isCurrent()) throw new Error('茶楼账号已切换，已取消图片上传。')

    const request: http.HttpRequest = http.createHttp()
    try {
      const part: http.MultiFormData = {
        name: 'source', contentType: ForumImageUpload.contentType(filename),
        remoteFileName: filename, filePath: filePath,
      }
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        // The native multipart implementation supplies its own boundary.
        header: {
          'Content-Type': 'multipart/form-data', 'Accept': 'application/json',
          'Authorization': 'Bearer ' + token, 'User-Agent': Constant.USER_AGENT,
        },
        multiFormDataList: [part], expectDataType: http.HttpDataType.STRING,
        usingCache: false, reuseConnections: false, connectTimeout: 30000, readTimeout: 120000,
        maxLimit: 1024 * 1024,
        // Uploads must not be redirected or replayed with account credentials.
        maxRedirects: 0,
      }
      let response: http.HttpResponse
      try {
        response = await request.request(Constant.IMAGE_BASE_URL + '/json', NetworkProxy.apply(options))
      } catch (e) {
        // Native exception strings can contain headers or URLs. Do not expose them.
        throw new Error('图片上传失败，请检查网络后重试')
      }
      if (!isCurrent()) throw new Error('茶楼账号已切换，已取消图片上传。')
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error('图片上传失败（HTTP ' + response.responseCode + '）')
      }
      if (typeof response.result !== 'string' || response.result.length > 1024 * 1024) {
        throw new Error('图片上传返回内容无效')
      }
      let body: UploadResponse
      try { body = JSON.parse(response.result) as UploadResponse }
      catch (e) { throw new Error('图片上传返回内容无效') }
      // Android uses display_url; iOS consumes the original image.url field.
      const source: string | undefined = body?.image?.display_url ?? body?.image?.url
      if (typeof source !== 'string' || !ForumImageUpload.isDisplayUrl(source)) {
        throw new Error('图片上传返回地址无效')
      }
      return source
    } finally {
      try { request.destroy() } catch (e) {}
    }
  }

  private static isLocalPath(path: string): boolean {
    return path.length > 0 && path.length <= 4096 && !/[\u0000-\u001f\u007f]/.test(path) &&
      (path.startsWith('/') || path.startsWith('file://'))
  }

  private static isSafeFilename(filename: string): boolean {
    return filename.length > 0 && filename.length <= 160 && filename !== '.' && filename !== '..' &&
      !/[\\/:*?"<>|\u0000-\u001f\u007f-\u009f]/.test(filename) && !/[. ]$/.test(filename)
  }

  private static contentType(filename: string): string {
    const extension: string = filename.substring(filename.lastIndexOf('.') + 1).toLowerCase()
    switch (extension) {
      case 'jpg': case 'jpeg': return 'image/jpeg'
      case 'png': return 'image/png'
      case 'gif': return 'image/gif'
      case 'webp': return 'image/webp'
      case 'avif': return 'image/avif'
      case 'heic': return 'image/heic'
      case 'heif': return 'image/heif'
      case 'bmp': return 'image/bmp'
      default: return 'application/octet-stream'
    }
  }

  private static isDisplayUrl(value: string): boolean {
    if (!value || value.length > 8192 || /[\s<>"'\\()[\]\u0000-\u001f\u007f]/.test(value)) return false
    try {
      const decoded: string = decodeURIComponent(value)
      if (/[\s<>"'\\()[\]\u0000-\u001f\u007f]/.test(decoded)) return false
      const parsed: url.URL = url.URL.parseURL(value)
      const base: url.URL = url.URL.parseURL(Constant.IMAGE_BASE_URL)
      return parsed.protocol === 'https:' && parsed.origin === base.origin &&
        !parsed.username && !parsed.password && parsed.pathname.length > 1 && !parsed.hash
    } catch (e) { return false }
  }
}
