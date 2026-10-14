import { Constant } from '../common/Constant'

/** One render property commits scale and translation together. */
export class ForumImagePose {
  scale: number = 1
  x: number = 0
  y: number = 0
  constructor(scale: number = 1, x: number = 0, y: number = 0) {
    this.scale = scale; this.x = x; this.y = y
  }
}

/** Absolute, render-equivalent image bounds used only for the return flight. */
export class ForumImageFrame {
  x: number = 0
  y: number = 0
  width: number = 0
  height: number = 0
  id: string = ''
  slot: number = -1
  constructor(x: number, y: number, width: number, height: number, id: string, slot: number) {
    this.x = x; this.y = y; this.width = width; this.height = height; this.id = id; this.slot = slot
  }
}

export class ForumImage {
  /** Finite magic check before caching/saving server bytes. Do not trust a
   * missing or mistaken Content-Type: a WebVPN login HTML is never an image.
   * Covers the raster containers supported by the current image pipeline.
   */
  static isImageHeader(bytes: number[]): boolean {
    if (bytes.length < 4) return false
    if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return true
    if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47 &&
      bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a) return true
    if (bytes.length >= 6 && String.fromCharCode(...bytes.slice(0, 6)).match(/^GIF8[79]a$/)) return true
    if (bytes.length >= 12 && String.fromCharCode(...bytes.slice(0, 4)) === 'RIFF' &&
      String.fromCharCode(...bytes.slice(8, 12)) === 'WEBP') return true
    if (bytes[0] === 0x42 && bytes[1] === 0x4d) return true
    if ((bytes[0] === 0x49 && bytes[1] === 0x49 && bytes[2] === 0x2a && bytes[3] === 0) ||
      (bytes[0] === 0x4d && bytes[1] === 0x4d && bytes[2] === 0 && bytes[3] === 0x2a)) return true
    // AVIF/HEIF use an ISO BMFF ftyp box, with a major or compatible brand.
    if (bytes.length >= 16 && String.fromCharCode(...bytes.slice(4, 8)) === 'ftyp') {
      const brands: string[] = ['avif', 'avis', 'heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1']
      if (brands.includes(String.fromCharCode(...bytes.slice(8, 12)))) return true
      const declared: number = bytes[0] * 16777216 + bytes[1] * 65536 + bytes[2] * 256 + bytes[3]
      for (let i: number = 16; i + 4 <= Math.min(bytes.length, declared); i += 4) {
        if (brands.includes(String.fromCharCode(...bytes.slice(i, i + 4)))) return true
      }
    }
    return false
  }

  static isRemote(url: string): boolean {
    return /^https?:\/\/[^\s<>]+$/i.test(url)
  }

  /** Same .md. thumbnail convention as upstream extractHighDefinitionImageUrl. */
  static original(url: string): string {
    if (!ForumImage.isRemote(url)) return ''
    if (url.startsWith(Constant.IMAGE_BASE_URL + '/')) {
      const boundary: number = url.search(/[?#]/)
      const path: string = boundary < 0 ? url : url.substring(0, boundary)
      const suffix: string = boundary < 0 ? '' : url.substring(boundary)
      return path.replace('.md.', '.') + suffix
    }
    return url
  }

  /** Only the known image host uses the upstream .md. preview convention.
   * Do not rewrite arbitrary hosts or signed/query-bearing originals.
   */
  static preview(url: string): string {
    if (!ForumImage.isRemote(url) || !url.startsWith(Constant.IMAGE_BASE_URL + '/') || /[?#]/.test(url) ||
      /\.md\.(?:png|jpe?g|gif|webp)$/i.test(url)) return url
    return url.replace(/\.(png|jpe?g|gif|webp)$/i, '.md.$1')
  }

  static filename(url: string): string {
    const clean: string = url.split(/[?#]/)[0]
    let name: string = clean.substring(clean.lastIndexOf('/') + 1)
    try { name = decodeURIComponent(name) } catch (e) {}
    name = name.replace(/[\\/:*?"<>|\u0000-\u001f]/g, '_').substring(0, 160)
    return name.length > 0 && name !== '.' && name !== '..' ? name : 'danxi-original.img'
  }

  static clampScale(scale: number): number {
    return Math.max(1, Math.min(8, scale))
  }

  static panLimit(viewWidth: number, viewHeight: number, imageWidth: number,
    imageHeight: number, scale: number, horizontal: boolean): number {
    if (viewWidth <= 0 || viewHeight <= 0 || imageWidth <= 0 || imageHeight <= 0) return 0
    // Fit width: tall originals remain vertically pannable even at scale 1.
    const fit: number = viewWidth / imageWidth
    return Math.max(0, ((horizontal ? imageWidth : imageHeight) * fit * scale -
      (horizontal ? viewWidth : viewHeight)) / 2)
  }

  /** Fit width, center images that fit the viewport, and start long images
   * at their upper edge. Offsets are relative to the viewport center. */
  static topOffset(viewWidth: number, viewHeight: number, imageWidth: number,
    imageHeight: number, scale: number = 1): number {
    if (viewWidth <= 0 || viewHeight <= 0 || imageWidth <= 1 || imageHeight <= 1) return 0
    return Math.max(0, (viewWidth * imageHeight / imageWidth * scale - viewHeight) / 2)
  }

  static constrainY(y: number, viewWidth: number, viewHeight: number,
    imageWidth: number, imageHeight: number, scale: number): number {
    const top: number = ForumImage.topOffset(viewWidth, viewHeight, imageWidth, imageHeight, scale)
    return top === 0 ? 0 : Math.max(-top, Math.min(top, y))
  }
  /** Constant-friction travel in vp; GestureEvent velocities are measured in vp/s. */
  static inertiaDistance(velocity: number, progress: number, durationMs: number): number {
    if (!Number.isFinite(velocity) || !Number.isFinite(progress) || durationMs <= 0) return 0
    const speed: number = Math.max(-6000, Math.min(6000, velocity))
    return speed * (1 - Math.exp(-6 * Math.max(0, Math.min(1, progress)) * durationMs / 1000)) / 6
  }

  static inertiaDuration(x: number, y: number): number {
    const speed: number = Math.min(6000, Math.max(Number.isFinite(x) ? Math.abs(x) : 0,
      Number.isFinite(y) ? Math.abs(y) : 0))
    return speed < 35 ? 0 : Math.min(1100, Math.max(180, Math.log(speed / 15) / 6 * 1000))
  }
}
