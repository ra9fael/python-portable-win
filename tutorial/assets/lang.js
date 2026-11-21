(function () {
  var data = window.TUTORIAL_I18N;
  if (!data) { return; }

  var STORAGE_KEY = 'portable-python-tutorial-lang';

  function normalize(value) {
    return value === 'en' ? 'en' : (value === 'zh' ? 'zh' : '');
  }

  function detectLang() {
    var fromQuery = '';
    try {
      fromQuery = normalize(new URLSearchParams(window.location.search).get('lang'));
    } catch (e) { /* ignore */ }
    if (fromQuery) { return fromQuery; }

    try {
      var saved = normalize(window.localStorage.getItem(STORAGE_KEY));
      if (saved) { return saved; }
    } catch (e) { /* ignore */ }

    var browser = (navigator.language || 'zh').toLowerCase();
    return browser.indexOf('en') === 0 ? 'en' : 'zh';
  }

  if (window.mermaid) {
    var css = getComputedStyle(document.documentElement);
    mermaid.initialize({
      startOnLoad: false,
      theme: 'base',
      themeVariables: {
        primaryColor: css.getPropertyValue('--bg2').trim(),
        primaryTextColor: css.getPropertyValue('--ink').trim(),
        primaryBorderColor: css.getPropertyValue('--accent').trim(),
        lineColor: css.getPropertyValue('--muted').trim(),
        fontFamily: "'Instrument Sans', 'Noto Sans SC', 'Microsoft YaHei', sans-serif",
        fontSize: '14px',
        clusterBkg: '#fbfaf6',
        clusterBorder: css.getPropertyValue('--rule').trim()
      },
      flowchart: { curve: 'basis', useMaxWidth: true }
    });
  }

  function renderMermaid(dict) {
    if (!window.mermaid) { return; }
    var nodes = Array.prototype.slice.call(document.querySelectorAll('pre.mermaid'));
    if (!nodes.length) { return; }
    nodes.forEach(function (node) {
      var key = node.getAttribute('data-i18n-mermaid');
      if (key && dict.mermaid[key] != null) {
        node.textContent = dict.mermaid[key];
      }
      node.removeAttribute('data-processed');
    });
    mermaid.run({ nodes: nodes });
  }

  function applyLang(lang) {
    var current = data[lang] || data.zh;

    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      var value = current.text[el.getAttribute('data-i18n')];
      if (typeof value === 'string') { el.innerHTML = value; }
    });

    document.querySelectorAll('[data-i18n-pre]').forEach(function (el) {
      var value = current.pre[el.getAttribute('data-i18n-pre')];
      if (typeof value === 'string') { el.innerHTML = value; }
    });

    document.querySelectorAll('[data-i18n-aria]').forEach(function (el) {
      var value = current.aria[el.getAttribute('data-i18n-aria')];
      if (typeof value === 'string') { el.setAttribute('aria-label', value); }
    });

    document.documentElement.lang = lang === 'en' ? 'en' : 'zh-CN';

    document.querySelectorAll('[data-lang-btn]').forEach(function (btn) {
      var active = btn.getAttribute('data-lang-btn') === lang;
      btn.classList.toggle('active', active);
      btn.setAttribute('aria-pressed', active ? 'true' : 'false');
    });

    try { window.localStorage.setItem(STORAGE_KEY, lang); } catch (e) { /* ignore */ }

    try {
      var url = new URL(window.location.href);
      url.searchParams.set('lang', lang);
      window.history.replaceState(null, '', url.toString());
    } catch (e) { /* file:// or restricted context */ }

    renderMermaid(current);
    window.dispatchEvent(new CustomEvent('tutorial:lang', { detail: { lang: lang } }));
  }

  document.querySelectorAll('[data-lang-btn]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      applyLang(normalize(btn.getAttribute('data-lang-btn')) || 'zh');
    });
  });

  applyLang(detectLang());
})();
