interface ForumHostRoute {
  origin: string
  encoded: string
}

/** Fixed public host translations from upstream WebVPNInterceptor's AES-CFB.
 * These are host names, not credentials. Keep paths and queries unchanged.
 */
export class ForumRoute {
  static readonly VPN_ORIGIN: string = 'https://webvpn.fudan.edu.cn'
  static readonly LOGIN_URL: string = ForumRoute.VPN_ORIGIN + '/login?cas_login=true'
  private static readonly HOSTS: ForumHostRoute[] = [
    { origin: 'https://forum.fduhole.com',
      encoded: '77726476706e69737468656265737421f6f853892a7e6e546b0086a09d1b203a46' },
    { origin: 'https://auth.fduhole.com',
      encoded: '77726476706e69737468656265737421f1e2559469366c45760785a9d6562c38' },
    { origin: 'https://image.fduhole.com',
      encoded: '77726476706e69737468656265737421f9fa409b227e6e546b0086a09d1b203ab8' },
    { origin: 'https://danke.fduhole.com',
      encoded: '77726476706e69737468656265737421f4f64f97227e6e546b0086a09d1b203a73' }
  ]

  static proxyUrl(value: string): string {
    for (const host of ForumRoute.HOSTS) {
      if (ForumRoute.hasOrigin(value, host.origin)) {
        return ForumRoute.VPN_ORIGIN + '/https/' + host.encoded + value.substring(host.origin.length)
      }
    }
    return ''
  }

  static directUrl(value: string): string {
    for (const host of ForumRoute.HOSTS) {
      const prefix = ForumRoute.VPN_ORIGIN + '/https/' + host.encoded
      if (ForumRoute.hasOrigin(value, prefix)) return host.origin + value.substring(prefix.length)
    }
    return value
  }

  private static hasOrigin(value: string, prefix: string): boolean {
    if (!value.startsWith(prefix)) return false
    const boundary = value.charAt(prefix.length)
    return boundary === '' || boundary === '/' || boundary === '?' || boundary === '#'
  }
}
