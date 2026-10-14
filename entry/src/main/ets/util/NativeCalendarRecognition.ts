import { deviceInfo } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { pdfService } from '@kit.PDFKit';

/** Native-only platform adapter, following ArkUI-X's documented .ts isolation:
 * https://gitee.com/arkui-x/docs/blob/master/zh-cn/application-dev/quick-start/platform-different-introduction.md
 * The shared ArkTS module never calls these capabilities on Android/iOS.
 * ArkTS syntax checks remain enabled. Native gallery UI uses ArkUI-X's
 * documented ignoreCrossPlatform setting with its own runtime platform guard.
 */
export class NativeCalendarRecognition {
  static supported(): boolean {
    const os = deviceInfo.osFullName;
    return (os.startsWith('HarmonyOS') || os.startsWith('OpenHarmony')) &&
      canIUse('SystemCapability.AI.OCR.TextRecognition');
  }

  static async recognize(map: image.PixelMap): Promise<string> {
    try {
      if (!NativeCalendarRecognition.supported()) throw new Error('Native calendar recognition unavailable');
      // @ts-ignore ArkUI-X: native-only call, guarded by OS and syscap above.
      const result = await textRecognition.recognizeText({ pixelMap: map }, { isDirectionDetectionSupported: false });
      // @ts-ignore ArkUI-X: native-only OCR result.
      return result.value;
    } finally { await map.release(); }
  }

  static async pdfText(path: string): Promise<string> {
    if (!NativeCalendarRecognition.supported() || !canIUse('SystemCapability.OfficeService.PDFService.Core')) {
      throw new Error('Native PDF calendar recognition unavailable');
    }
    // @ts-ignore ArkUI-X: native-only PDF constructor, guarded by OS/syscap.
    const document = new pdfService.PdfDocument();
    try {
      // @ts-ignore ArkUI-X: native-only parser and result enum.
      if (document.loadDocument(path) !== pdfService.ParseResult.PARSE_SUCCESS) throw new Error('Invalid official PDF');
      let text = '';
      // @ts-ignore ArkUI-X: native-only PDF page count.
      const count = Math.min(3, document.getPageCount());
      for (let index = 0; index < count; index++) {
        // @ts-ignore ArkUI-X: native-only PDF page.
        const page = document.getPage(index);
        try {
          // @ts-ignore ArkUI-X: native-only text extraction.
          const content = page.getTextContent();
          // @ts-ignore ArkUI-X: native-only PDF rasterization followed by guarded on-device OCR.
          text += content || await NativeCalendarRecognition.recognize(page.getPagePixelMap());
        } finally {
          // @ts-ignore ArkUI-X: native-only resource release.
          page.release();
        }
      }
      return text;
    } finally {
      // @ts-ignore ArkUI-X: native-only resource release.
      document.releaseDocument();
    }
  }
}
