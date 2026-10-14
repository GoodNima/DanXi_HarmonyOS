/* Offline Markdown/TeX renderer. Posts are data, never executable markup. */
(function (root) {
  'use strict';
  const escape = value => String(value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const safeLink = value => {
    try { const url = new URL(value); return /^(https?:)$/.test(url.protocol) && !url.username && !url.password ? url.href : ''; }
    catch (_) { return ''; }
  };
  const md = root.marked || (typeof require === 'function' ? require('./marked.js') : null);
  const tex = root.katex || (typeof require === 'function' ? require('./katex.min.js') : null);
  const math = (value, display) => tex.renderToString(value, {
    displayMode: display, throwOnError: false, trust: false, strict: 'ignore',
    maxExpand: 1000, maxSize: 20, output: 'htmlAndMathml'
  });
  let stickerImages = {};
  md.use({
    gfm: true, breaks: true, async: false,
    extensions: [{
      name: 'forumMath', level: 'inline', start: source => source.indexOf('$'),
      tokenizer(source) {
        const match = /^(\$\$)([\s\S]+?)\$\$|^\$([^$\n]+?)\$(?!\$)/.exec(source);
        if (match) return { type: 'forumMath', raw: match[0], value: match[2] || match[3], display: !!match[1] };
      },
      renderer: token => '<span class="math-scroll' + (token.display ? ' display-math' : '') + '">' + math(token.value, token.display) + '</span>'
    }],
    renderer: {
      html(token) {
        // The original client renders <audit> as marked text. Other user HTML
        // is shown literally, including script, style and SVG tags.
        return token.text.split(/(<\/?audit>)/gi).map(part => /^<audit>$/i.test(part) ? '<mark>' :
          /^<\/audit>$/i.test(part) ? '</mark>' : escape(part)).join('');
      },
      image(token) {
        const id = String(token.href).replace(/^danxi_/, 'dx_');
        const source = /^dx_[a-z0-9_]+$/i.test(id) && Object.prototype.hasOwnProperty.call(stickerImages, id) ? stickerImages[id] : '';
        // Only checksum-verified bundled assets supplied by the native bridge.
        return /^data:image\/(?:png|webp);base64,[A-Za-z0-9+/=]+$/.test(source) ?
          '<img class="forum-sticker" src="' + source + '" alt="' + escape(token.text || '表情') + '">' : escape('[' + (token.text || 'image') + ']');
      },
      link(token) {
        const url = safeLink(token.href);
        const label = this.parser.parseInline(token.tokens);
        return url ? '<a href="' + escape(url) + '">' + label + '</a>' : label;
      },
      code(token) {
        const language = (token.lang || '').split(/\s/)[0].toLowerCase();
        const aliases = { js: 'javascript', ts: 'typescript', py: 'python', sh: 'bash', html: 'markup' };
        const name = aliases[language] || language;
        const grammar = root.Prism && root.Prism.languages[name];
        const body = grammar ? root.Prism.highlight(token.text, grammar, name) : escape(token.text);
        return '<pre><code>' + body + '</code></pre>';
      }
    }
  });
  function render(content, stickers = {}) {
    stickerImages = stickers;
    try { return md.parse(String(content).slice(0, 100000)); }
    finally { stickerImages = {}; }
  }
  // Rectangles come from native DOM line layout, not a guessed number of ems.
  // A formula is atomic so its superscripts/descenders are retained. Horizontal
  // rules have no text range but still occupy a complete visual line. Ordinary
  // code/table text counts real lines so previews cannot grow unbounded.
  function previewExtent(rectangles, top, maxLines = 4) {
    const lines = [];
    const sorted = rectangles.filter(rect => Number.isFinite(rect.top) && Number.isFinite(rect.bottom) && rect.bottom > rect.top)
      .slice().sort((first, second) => first.top - second.top || first.bottom - second.bottom);
    for (const rect of sorted) {
      const previous = lines[lines.length - 1];
      if (previous && rect.top < previous.bottom - 0.5) previous.bottom = Math.max(previous.bottom, rect.bottom);
      else lines.push({ top: rect.top, bottom: rect.bottom });
    }
    const count = Math.max(1, Math.floor(maxLines));
    const truncated = lines.length > count;
    return { truncated, height: truncated ? Math.max(1, Math.ceil(lines[count - 1].bottom - top + 3)) : 0 };
  }
  const api = { render, safeLink, math, previewExtent };
  if (typeof module === 'object' && module.exports) module.exports = api;
  root.ForumRich = api;
  if (!root.document) return;
  const body = document.getElementById('content');
  const more = document.createElement('div');
  more.className = 'preview-more'; more.textContent = '…'; more.hidden = true;
  more.setAttribute('aria-hidden', 'true'); body.after(more);
  let reported = -1;
  let hasContent = false;
  function visualRectangles() {
    const rectangles = [];
    const atomic = '.math-scroll,hr,.forum-sticker';
    body.querySelectorAll(atomic).forEach(element => {
      const rect = element.getBoundingClientRect();
      if (rect.width > 0 && rect.height > 0) rectangles.push(rect);
    });
    const walker = document.createTreeWalker(body, root.NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      if (!node.textContent.trim() || node.parentElement.closest(atomic)) continue;
      const range = document.createRange(); range.selectNodeContents(node);
      // jsdom deliberately has no layout engine; the device supplies this API.
      if (typeof range.getClientRects === 'function') {
        for (const rect of range.getClientRects()) if (rect.width > 0 && rect.height > 0) rectangles.push(rect);
      }
    }
    return rectangles;
  }
  function measure() {
    // The initial empty article is not a successful post layout. In
    // particular its 1px report must not dismiss the native startup hint.
    if (!root.document || !hasContent) return;
    body.style.maxHeight = '';
    more.hidden = true;
    if (body.classList.contains('preview')) {
      const extent = previewExtent(visualRectangles(), body.getBoundingClientRect().top);
      if (extent.truncated) { body.style.maxHeight = extent.height + 'px'; more.hidden = false; }
    }
    const height = Math.ceil(body.getBoundingClientRect().height + (more.hidden ? 0 : more.getBoundingClientRect().height) + 1);
    if (height === reported) return;
    reported = height;
    if (root.ForumBridge) root.ForumBridge.layout(String(height));
  }
  api.setContent = data => {
    document.documentElement.dataset.theme = data.dark ? 'dark' : 'light';
    body.style.fontSize = Math.max(10, Math.min(48, data.fontSize || 16)) + 'px';
    body.classList.toggle('preview', !!data.preview);
    // Final sanitation includes generated Markdown, code and KaTeX markup.
    body.innerHTML = DOMPurify.sanitize(render(data.content, data.stickers), {
      FORBID_TAGS: ['script', 'style', 'iframe', 'object', 'embed', 'video', 'audio', 'form'],
      FORBID_ATTR: ['srcset', 'id', 'name'], ALLOW_DATA_ATTR: false
    });
    // KaTeX repeats the color on individual glyph spans. Adapt every named
    // foreground, rather than only its outer wrapper, in the dark palette.
    if (data.dark) {
      const palette = { blue: '#64A8FF', 'rgb(0, 0, 255)': '#64A8FF',
        gray: '#AEAEB2', grey: '#AEAEB2', 'rgb(128, 128, 128)': '#AEAEB2',
        black: '#FFFFFF', 'rgb(0, 0, 0)': '#FFFFFF' };
      body.querySelectorAll('.katex [style]').forEach(element => {
        const color = palette[element.style.color.toLowerCase()];
        if (color) element.style.setProperty('color', color, 'important');
      });
    }
    hasContent = true;
    reported = -1;
    requestAnimationFrame(measure);
    document.fonts.ready.then(measure);
  };
  body.addEventListener('click', event => {
    const anchor = event.target.closest('a');
    if (!anchor) return;
    event.preventDefault();
    const address = safeLink(anchor.getAttribute('href'));
    if (address && root.ForumBridge) root.ForumBridge.link(address);
  });
  new ResizeObserver(measure).observe(body);
})(typeof window === 'object' ? window : globalThis);

