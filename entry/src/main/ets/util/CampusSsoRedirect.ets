import { http } from '@kit.NetworkKit'

/** Obtain the real redirect status before the SDK's maxRedirects error hides
 * it. Returning false stops native following; HttpUtil retains manual policy. */
export class CampusSsoRedirect implements http.HttpInterceptor {
  interceptorType: http.InterceptorType = http.InterceptorType.REDIRECTION

  async interceptorHandle(_request: http.HttpRequestContext, _response: http.HttpResponse): Promise<http.ChainContinue> {
    return false
  }

  static attach(request: http.HttpRequest): boolean {
    const chain = new http.HttpInterceptorChain()
    return chain.addChain([new CampusSsoRedirect()]) && chain.apply(request)
  }
}
