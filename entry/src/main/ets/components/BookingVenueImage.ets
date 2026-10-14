import { image } from '@kit.ImageKit'
import { BookingImageCache } from '../util/BookingImageCache'
import { BookingBitmapCache, VenueBitmapLease, VenueImageReader } from '../util/BookingBitmapCache'
import { ReservationIcons } from '../common/ReservationIcons'
import { ThemeColors } from '../common/Theme'

@Component
export struct BookingVenueImage {
  @Prop @Watch('changed') token: string = ''
  @Prop @Watch('changed') large: boolean = false
  @Prop name: string = ''
  imageReader: VenueImageReader = (value: string): Promise<ArrayBuffer> => BookingImageCache.read(value)
  @State private bitmap: image.PixelMap | undefined = undefined
  @State private animateArrival: boolean = false
  private active: boolean = false
  private revision: number = 0
  private lease: VenueBitmapLease | undefined = undefined
  private currentKey: string = ''
  aboutToAppear(): void { this.active = true; this.changed() }
  aboutToDisappear(): void { this.active = false; this.revision++; this.clear() }
  private clear(): void { this.bitmap = undefined; this.animateArrival = false; this.lease?.release(); this.lease = undefined; this.currentKey = '' }
  changed(): void {
    if (!this.active) return
    const key: string = BookingBitmapCache.identity(this.token, this.large)
    if (key === this.currentKey && this.lease !== undefined) return
    this.revision++
    if (!this.token) { this.clear(); return }
    const cached = BookingBitmapCache.retain(this.token, this.large)
    this.currentKey = key
    if (cached !== undefined) this.use(cached)
    else { this.clear(); this.currentKey = key; this.load(this.revision) }
  }
  private use(lease: VenueBitmapLease, animated: boolean = false): void {
    const previous = this.lease
    this.lease = lease; this.animateArrival = animated
    if (animated) {
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => { this.bitmap = lease.bitmap })
    } else { this.bitmap = lease.bitmap }
    previous?.release()
  }
  private async load(revision: number): Promise<void> {
    const token = this.token, key = this.currentKey
    try {
      const lease = await BookingBitmapCache.acquire(token, this.large, this.imageReader)
      if (!this.active || revision !== this.revision || key !== BookingBitmapCache.identity(this.token, this.large)) { lease.release(); return }
      this.use(lease, true)
    } catch (error) { /* An optional venue photo keeps its category placeholder on failure. */ }
  }
  build() {
    Stack({ alignContent: Alignment.Center }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(ReservationIcons.placeholder(this.name)).fontSize(30).fontWeight(FontWeight.Regular)
          .fontColor([ThemeColors.primary]).id('booking-placeholder-symbol')
      }.width(40).height(40).opacity(this.bitmap === undefined ? 1 : 0).id('booking-placeholder-frame')
      if (this.bitmap !== undefined) {
        Image(this.bitmap).width('100%').height('100%').objectFit(ImageFit.Cover)
          .transition(this.animateArrival ? TransitionEffect.asymmetric(TransitionEffect.OPACITY, TransitionEffect.IDENTITY) : TransitionEffect.IDENTITY)
          .id('booking-loaded-image')
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.campus_search_surface')).borderRadius(12).clip(true).accessibilityLevel('no-hide-descendants')
  }
}
