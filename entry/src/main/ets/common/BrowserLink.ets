import { common } from '@kit.AbilityKit'
import { url } from '@kit.ArkTS'

/** Public campus links are handled by the default system browser. */
export class BrowserLink {
  static normalize(value: string): string {
    try {
      const parsed = new url.URL(value.trim())
      if ((parsed.protocol !== 'https:' && parsed.protocol !== 'http:') || !parsed.hostname ||
        parsed.username || parsed.password) return ''
      return parsed.toString()
    } catch (e) { return '' }
  }

  static async open(context: common.UIAbilityContext, value: string): Promise<void> {
    const address = BrowserLink.normalize(value)
    if (!address) throw new Error('Invalid public URL')
    // viewData is supported by ArkUI-X; openLink is not available on both targets.
    await context.startAbility({ action: 'ohos.want.action.viewData', uri: address,
      entities: ['entity.system.browsable'] })
  }
}
