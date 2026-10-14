import { FduAuthPolicy } from '../model/FduAuth'

/** Presentation fixes for the official ID pages; never rebuild the CAS context. */
export class FduAuthWebPage {
  // Only the official decorative backdrop. Captcha/QR images and form controls
  // keep their own backgrounds. The stylesheet survives Vue's delayed rendering.
  static readonly PLAIN_BACKGROUND_SCRIPT: string = '(function(){' +
    'if(location.origin!=="https://id.fudan.edu.cn"||window.top!==window)return;' +
    'function apply(){if(!document.head||document.getElementById("danxi-plain-background"))return;' +
    'const style=document.createElement("style");style.id="danxi-plain-background";' +
    'style.textContent="html,body,#app,.topicPreview{background-image:none!important;background-color:#fff!important}' +
    '.topicCarousel{display:none!important}.topicPreview{--box_text_color:#303133;--box_input_text_color:#303133;}";' +
    'document.head.appendChild(style);}' +
    'if(document.head)apply();else document.addEventListener("DOMContentLoaded",apply,{once:true});})()'

  static mobileLoginUrl(url: string): string {
    if (!FduAuthPolicy.isIdUrl(url)) return url
    // The authentication server selects /ac-h5/ for Android/iPhone browsers.
    // Retain every query/hash byte, including lck, entityId and theme.
    return url.replace(/^(https:\/\/id\.fudan\.edu\.cn(?::443)?)\/ac\//i, '$1/ac-h5/')
  }

  static mobileUserAgent(userAgent: string): string {
    // Keep the actual engine version; older ID servers do not recognize OpenHarmony.
    if (/Android|iPhone|iPod/i.test(userAgent) && /Mobile/i.test(userAgent)) return userAgent
    return userAgent + ' Android Mobile'
  }

  static readonly VIEWPORT_SCRIPT: string = '(function(){' +
    'if(location.origin!=="https://id.fudan.edu.cn"||window.top!==window)return;' +
    'if(window.__danxiViewport)return;window.__danxiViewport=true;' +
    'const value="width=device-width, initial-scale=1, minimum-scale=0.5, maximum-scale=5, user-scalable=yes";' +
    'function apply(){' +
    'if(!document.head)return;' +
    'let metas=document.querySelectorAll("meta[name=viewport]");' +
    'if(!metas.length){const m=document.createElement("meta");m.name="viewport";document.head.appendChild(m);metas=[m];}' +
    'metas.forEach(function(m){if(m.content!==value)m.content=value;});}' +
    'apply();' +
    'if(document.head)new MutationObserver(apply).observe(document.head,' +
    '{childList:true,subtree:true,attributes:true,attributeFilter:["content","name"]});' +
    '})()'

  static fillScript(studentId: string, password: string): string {
    // JSON quoting protects special characters; check origin again after redirects.
    // Mobile inputs have no IDs. Restrict the fallback to the password login form,
    // so an SMS/OTP field is never filled with an account password.
    return '(function(){' +
      'if(location.origin!=="https://id.fudan.edu.cn"||window.top!==window)return "wait";' +
      'let u=document.getElementById("login-username");' +
      'let p=document.getElementById("login-password");' +
      'let b=document.querySelector(".el-button.content_submit");' +
      'if(!u||!p){' +
      'p=document.querySelector(".content_input form.login-form input[type=password]");' +
      'if(!p)return "wait";' +
      'const form=p.closest("form.login-form");' +
      'u=form.querySelector(".el-form-item:first-child input");' +
      'b=form.closest(".content_input").querySelector(".el-button.content_submit");}' +
      'if(!u||!p||u===p||!b||u.disabled||p.disabled||' +
      '!u.getClientRects().length||!p.getClientRects().length)return "wait";' +
      'u.value=' + JSON.stringify(studentId) + ';u.dispatchEvent(new Event("input",{bubbles:true}));' +
      'p.value=' + JSON.stringify(password) + ';p.dispatchEvent(new Event("input",{bubbles:true}));' +
      'Promise.resolve().then(function(){if(!b.disabled)b.click();});return "filled";})()'
  }
}
