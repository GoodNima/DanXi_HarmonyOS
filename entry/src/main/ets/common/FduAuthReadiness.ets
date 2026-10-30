/** Local, read-only readiness checks for the official ID page after its HTML shell loads. */
interface FduAuthDomWire {
  version?: number
  documentState?: string
  visibleControls?: number
  visibleChallenges?: number
  failed?: boolean
}

export class FduAuthDomSample {
  ready: boolean = false
  documentState: string = 'unknown'
  visibleControls: number = 0
  visibleChallenges: number = 0
  reason: string = 'not-sampled'

  diagnostics(): string {
    return 'idDomReady=' + String(this.ready) + '; documentState=' + this.documentState +
      '; visibleControls=' + String(this.visibleControls) + '; visibleChallenges=' + String(this.visibleChallenges) +
      '; readinessReason=' + this.reason
  }
}

export class FduAuthReadiness {
  // Geometry/style and known control presence only: no values, text, URLs, cookies,
  // credentials, clicks, submits or resource loads. Generic support links do not count.
  static readonly SCRIPT: string = '(function(){try{' +
    'function visible(e){' +
    'if(e.tagName==="IMG"&&(!e.complete||e.naturalWidth<=0))return false;' +
    'if(e.disabled||!e.getClientRects().length)return false;' +
    'const r=e.getBoundingClientRect();if(r.width<=1||r.height<=1)return false;' +
    'for(let n=e;n&&n.nodeType===1;n=n.parentElement){' +
    'const s=getComputedStyle(n);if(n.hidden||s.display==="none"||s.visibility==="hidden"||' +
    's.visibility==="collapse"||(s.opacity!==""&&Number(s.opacity)===0))return false;}return true;}' +
    'function count(selector){const nodes=document.querySelectorAll(selector);let total=0;' +
    'for(let i=0;i<nodes.length&&i<160;i++){if(visible(nodes[i]))total++;if(total>=64)break;}return total;}' +
    'const controls=count("#login-username,#login-password,#username,#password,#mobileUsername,#mobilePassword,"+' +
    '"form.login-form input:not([type=hidden]),form.login-form button,.content_input input:not([type=hidden]),"+' +
    '".content_input button,button.content_submit,input.content_submit,input[type=password],input[autocomplete=username],"+' +
    '"input[autocomplete=current-password],input[autocomplete=one-time-code]");' +
    'const challenges=count("img[id*=qr i],img[class*=qr i],canvas[id*=qr i],canvas[class*=qr i],"+' +
    '"img[id*=captcha i],img[class*=captcha i],img[id*=verify i],img[class*=verify i],.qrcode canvas,.qr-code canvas");' +
    'return JSON.stringify({version:1,documentState:document.readyState,visibleControls:controls,visibleChallenges:challenges});' +
    '}catch(e){return JSON.stringify({version:1,failed:true});}})()'

  static parse(raw: string): FduAuthDomSample {
    const sample = new FduAuthDomSample()
    sample.reason = 'invalid-result'
    if (!raw || raw.length > 2048) return sample
    let text = raw
    // ArkWeb can wrap a JavaScript string result in one additional JSON string.
    for (let depth: number = 0; depth < 2; depth++) {
      try {
        const value = JSON.parse(text) as FduAuthDomWire | string
        if (typeof value === 'string') { text = value; continue }
        if (value === null || typeof value !== 'object' || Array.isArray(value) || value.version !== 1) return sample
        if (value.failed === true) { sample.reason = 'dom-check-failed'; return sample }
        if (!FduAuthReadiness.validCount(value.visibleControls) || !FduAuthReadiness.validCount(value.visibleChallenges)) return sample
        sample.documentState = value.documentState === 'loading' || value.documentState === 'interactive' ||
          value.documentState === 'complete' ? value.documentState : 'unknown'
        sample.visibleControls = value.visibleControls as number
        sample.visibleChallenges = value.visibleChallenges as number
        sample.ready = sample.visibleControls + sample.visibleChallenges > 0
        sample.reason = sample.ready ? 'visible-controls' : 'dom-pending'
        return sample
      } catch (e) { return sample }
    }
    return sample
  }

  private static validCount(value: number | undefined): boolean {
    return typeof value === 'number' && Number.isInteger(value) && value >= 0 && value <= 64
  }
}

export interface FduAuthReadinessCallbacks {
  evaluate: () => Promise<string>
  onSample: (sample: FduAuthDomSample) => void
  onReady: (sample: FduAuthDomSample) => void
  onTimeout: (sample: FduAuthDomSample) => void
}

/** One DOM evaluation at a time. Cancellation/navigation replacement discards late results. */
export class FduAuthReadinessProbe {
  private callbacks: FduAuthReadinessCallbacks
  private intervalMs: number
  private timeoutMs: number
  private sequence: number = 0
  private active: boolean = false
  private evaluating: boolean = false
  private queuedSequence: number = -1
  private timer: number = -1
  private deadline: number = -1
  private last: FduAuthDomSample = new FduAuthDomSample()

  constructor(callbacks: FduAuthReadinessCallbacks, intervalMs: number = 500, timeoutMs: number = 15000) {
    this.callbacks = callbacks
    this.intervalMs = Number.isFinite(intervalMs) && intervalMs > 0 ? intervalMs : 500
    this.timeoutMs = Number.isFinite(timeoutMs) && timeoutMs > 0 ? timeoutMs : 15000
  }

  start(): void {
    this.cancel()
    this.active = true
    this.last = new FduAuthDomSample()
    const sequence: number = this.sequence
    this.deadline = setTimeout(() => {
      if (!this.current(sequence)) return
      const sample = this.last
      this.cancel()
      this.callbacks.onTimeout(sample)
    }, this.timeoutMs)
    this.requestSample(sequence)
  }

  cancel(): void {
    this.sequence++
    this.active = false
    this.queuedSequence = -1
    if (this.timer >= 0) clearTimeout(this.timer)
    if (this.deadline >= 0) clearTimeout(this.deadline)
    this.timer = -1; this.deadline = -1
  }

  isRunning(): boolean { return this.active }

  private current(sequence: number): boolean { return this.active && this.sequence === sequence }

  private requestSample(sequence: number): void {
    if (!this.current(sequence)) return
    if (this.evaluating) { this.queuedSequence = sequence; return }
    this.sample(sequence)
  }

  private async sample(sequence: number): Promise<void> {
    this.evaluating = true
    let sample = new FduAuthDomSample()
    try { sample = FduAuthReadiness.parse(await this.callbacks.evaluate()) }
    catch (e) { sample.reason = 'evaluation-failed' }
    this.evaluating = false
    if (!this.current(sequence)) {
      const queued: number = this.queuedSequence
      this.queuedSequence = -1
      this.requestSample(queued)
      return
    }
    this.last = sample
    this.callbacks.onSample(sample)
    if (!this.current(sequence)) return
    if (sample.ready) {
      this.cancel()
      this.callbacks.onReady(sample)
    } else {
      this.timer = setTimeout(() => { this.requestSample(sequence) }, this.intervalMs)
    }
  }
}
