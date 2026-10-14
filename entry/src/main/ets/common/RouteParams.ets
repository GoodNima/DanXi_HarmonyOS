/**
 * Typed route parameters.
 *
 * ArkTS forbids untyped object literals (`arkts-no-untyped-obj-literals`), and
 * `router.pushUrl({ params })` types the field as plain `Object`, so a nested
 * literal would not compile. Classes it is.
 */

/** pages/ForumDetailPage — the hole to open. */
export class HoleRouteParams {
  holeId: number = 0
  floorId: number = 0

  constructor(holeId: number, floorId: number = 0) {
    this.holeId = holeId
    this.floorId = floorId
  }
}

/** Decoded source image, carried into the destination before its first layout. */
export class ImageOpening {
  id: string = ''
  thumbnail: string = ''
  width: number = 0
  height: number = 0
  constructor(id: string, thumbnail: string, width: number, height: number) {
    this.id = id; this.thumbnail = thumbnail; this.width = width; this.height = height
  }
  static valid(value: ImageOpening | undefined): boolean {
    return value !== undefined && value !== null && typeof value.id === 'string' && value.id.length > 0 &&
      typeof value.thumbnail === 'string' && value.thumbnail.length > 0 &&
      Number.isFinite(value.width) && value.width > 1 && Number.isFinite(value.height) && value.height > 1
  }
}

export class ImageReturnTarget {
  source: string
  opening: ImageOpening
  constructor(source: string, opening: ImageOpening) { this.source = source; this.opening = opening }
}

export class ImageRouteParams {
  source: string
  sources: string[] = []
  opening: ImageOpening | undefined = undefined
  targets: ImageReturnTarget[] = []
  constructor(source: string, sources: string[] = [], opening: ImageOpening | undefined = undefined,
    targets: ImageReturnTarget[] = []) {
    this.source = source
    this.sources = sources.slice()
    this.opening = opening
    this.targets = targets.slice()
  }
}

/** pages/ForumEditorPage — the division a new hole is posted into. */
export class EditorRouteParams {
  divisionId: number = 0
  divisionName: string = ''

  constructor(divisionId: number, divisionName: string) {
    this.divisionId = divisionId
    this.divisionName = divisionName
  }
}

export class SettingsRouteParams {
  section: string
  constructor(section: string) { this.section = section }
}
