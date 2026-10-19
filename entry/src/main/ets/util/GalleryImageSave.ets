import { common } from '@kit.AbilityKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { fileIo as fs, fileUri } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { ForumImage } from '../model/ForumImage'

/** System confirmation grants only the selected destination URI. No broad album permission. */
export class GalleryImageSave {
  // ArkUI-X's documented runtime platform boundary. Gallery and SaveButton
  // are native HarmonyOS capabilities, so never invoke them on Android/iOS.
  static supported(): boolean {
    const os: string = deviceInfo.osFullName
    return !['Android', 'iOS', 'iPadOS', 'macOS'].some((platform: string) => os.startsWith(platform)) &&
      canIUse('SystemCapability.FileManagement.PhotoAccessHelper.Core')
  }
  static extension(bytes: number[]): string {
    if (!ForumImage.isImageHeader(bytes)) throw new Error('Invalid image')
    if (bytes[0] === 0xff) return 'jpg'
    if (bytes[0] === 0x89) return 'png'
    if (String.fromCharCode(...bytes.slice(0, 3)) === 'GIF') return 'gif'
    if (String.fromCharCode(...bytes.slice(0, 4)) === 'RIFF') return 'webp'
    if (bytes[0] === 0x42) return 'bmp'
    if (bytes[0] === 0x49 || bytes[0] === 0x4d) return 'tiff'
    if (String.fromCharCode(...bytes.slice(4, 8)) === 'ftyp') {
      for (let i: number = 8; i + 4 <= bytes.length; i += 4) {
        if (['avif', 'avis'].includes(String.fromCharCode(...bytes.slice(i, i + 4)))) return 'avif'
      }
      return 'heic'
    }
    throw new Error('Unsupported image')
  }

  static async save(context: common.UIAbilityContext, path: string): Promise<string> {
    if (!GalleryImageSave.supported()) throw new Error('Native gallery unavailable')
    const input: fs.File = await fs.open(path, fs.OpenMode.READ_ONLY)
    const prefix: ArrayBuffer = new ArrayBuffer(64)
    let count: number = 0
    try { count = await fs.read(input.fd, prefix, { length: 64 }) }
    finally { await fs.close(input) }
    const extension: string = GalleryImageSave.extension(Array.from(new Uint8Array(prefix, 0, count)))
    const staged: string = path + '.' + extension
    const helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context)
    try {
      await fs.copyFile(path, staged)
      const uris: string[] = await helper.showAssetsCreationDialog([fileUri.getUriFromPath(staged)],
        [{ title: 'DanTa-' + Date.now(), fileNameExtension: extension, photoType: photoAccessHelper.PhotoType.IMAGE }])
      if (uris.length === 0) return ''
      const destination: fs.File = await fs.open(uris[0], fs.OpenMode.WRITE_ONLY)
      try { await fs.copyFile(staged, destination.fd) }
      finally { await fs.close(destination) }
      return uris[0]
    } finally {
      try { await fs.unlink(staged) } catch (e) {}
      try { await helper.release() } catch (e) {}
    }
  }
}
