import { fileIo as fs } from '@kit.CoreFileKit'
import { BrowserLink } from '../common/BrowserLink'
import { ForumImage } from '../model/ForumImage'
import { ForumImageCache } from './ForumImageCache'

/** Save original bytes, reusing the full-resolution cache without re-encoding
 * a preview. A .md. thumbnail is never accepted as the original cache key.
 */
export class OriginalImageDownload {
  private load: ForumImageCache = new ForumImageCache()
  private cancelled: boolean = false

  async download(source: string, path: string): Promise<void> {
    const address: string = BrowserLink.normalize(source)
    const original: string = ForumImage.original(address)
    if (!original) throw new Error('图片地址无效')
    if (this.cancelled) throw new Error('已取消下载')
    const cacheDir: string = path.substring(0, path.lastIndexOf('/'))
    const cached: string = await this.load.load(original, cacheDir)
    if (this.cancelled) throw new Error('已取消下载')
    await fs.copyFile(cached.substring('file://'.length), path)
    if (this.cancelled) { try { await fs.unlink(path) } catch (e) {}; throw new Error('已取消下载') }
  }

  cancel(): void { this.cancelled = true; this.load.cancel() }
}
