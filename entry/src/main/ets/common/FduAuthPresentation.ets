/** Native sheet owns the presentation; the Web component owns authentication.
 * These callbacks hold no credentials or URL parameters. */
export class FduAuthPresentation {
  requestId: number = 0
  close: () => void = () => {}
  deactivate: () => void = () => {}
  settle: () => void = () => {}
  isCurrent: () => boolean = (): boolean => false
  refreshAppearance: () => void = () => {}
}
