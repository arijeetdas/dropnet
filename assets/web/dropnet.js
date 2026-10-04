/* DropNet web: shared behaviour of the Web Portal and Temporary Share pages.
   Served at /_dropnet/dropnet.js. Presentation only; no API calls here. */
(function () {
  'use strict';

  var root = document.documentElement;
  var STORAGE_KEY = 'dropnet-theme';
  var darkQuery = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;

  function currentTheme() {
    var forced = root.getAttribute('data-theme');
    if (forced === 'light' || forced === 'dark') return forced;
    return darkQuery && darkQuery.matches ? 'dark' : 'light';
  }

  function syncThemeColor() {
    var color = getComputedStyle(root).getPropertyValue('--bg').trim();
    if (!color) return;
    document.querySelectorAll('meta[name="theme-color"]').forEach(function (meta) {
      meta.setAttribute('content', color);
    });
  }

  function applyTheme(theme) {
    root.setAttribute('data-theme', theme);
    try { localStorage.setItem(STORAGE_KEY, theme); } catch (_) {}
    syncThemeColor();
  }

  function toggleTheme(event) {
    var next = currentTheme() === 'dark' ? 'light' : 'dark';
    var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (!document.startViewTransition || reduce) {
      applyTheme(next);
      return;
    }
    var rect = event.currentTarget.getBoundingClientRect();
    var x = rect.left + rect.width / 2;
    var y = rect.top + rect.height / 2;
    var radius = Math.hypot(Math.max(x, innerWidth - x), Math.max(y, innerHeight - y));
    var transition = document.startViewTransition(function () { applyTheme(next); });
    transition.ready.then(function () {
      root.animate(
        { clipPath: ['circle(0px at ' + x + 'px ' + y + 'px)', 'circle(' + radius + 'px at ' + x + 'px ' + y + 'px)'] },
        { duration: 560, easing: 'cubic-bezier(0.3, 0, 0, 1)', pseudoElement: '::view-transition-new(root)' }
      );
    }).catch(function () {});
  }

  document.querySelectorAll('[data-theme-toggle]').forEach(function (button) {
    button.addEventListener('click', toggleTheme);
  });
  if (darkQuery && darkQuery.addEventListener) {
    darkQuery.addEventListener('change', syncThemeColor);
  }
  if (root.hasAttribute('data-theme')) syncThemeColor();

  // PIN show/hide.
  document.querySelectorAll('[data-pin-reveal]').forEach(function (button) {
    button.addEventListener('click', function () {
      var input = button.parentElement.querySelector('input');
      if (!input) return;
      var show = input.type === 'password';
      input.type = show ? 'text' : 'password';
      button.classList.toggle('is-on', show);
      button.setAttribute('aria-label', show ? 'Hide PIN' : 'Show PIN');
      input.focus();
    });
  });

  // Visual confirmation on direct download links.
  document.addEventListener('click', function (event) {
    var link = event.target.closest ? event.target.closest('[data-download]') : null;
    if (!link) return;
    link.classList.add('is-started');
    clearTimeout(link._dnTimer);
    link._dnTimer = setTimeout(function () { link.classList.remove('is-started'); }, 2600);
  });

  // Expiry countdowns: <dd data-countdown data-expires-at="ms" data-started-at="ms">.
  document.querySelectorAll('[data-countdown]').forEach(function (el) {
    var expiresAt = Number(el.getAttribute('data-expires-at'));
    var startedAt = Number(el.getAttribute('data-started-at')) || Date.now();
    var bar = document.querySelector('[data-countdown-bar]');
    var holder = el.closest('div');
    function pad(n) { return String(n).padStart(2, '0'); }
    function tick() {
      var remaining = Math.max(0, Math.round((expiresAt - Date.now()) / 1000));
      var h = Math.floor(remaining / 3600);
      var m = Math.floor((remaining % 3600) / 60);
      var s = remaining % 60;
      el.textContent = remaining === 0 ? 'Expired' : (h > 0 ? h + ':' + pad(m) + ':' + pad(s) : m + ':' + pad(s));
      if (bar) {
        var total = Math.max(1, expiresAt - startedAt);
        bar.style.setProperty('--p', Math.max(0, Math.min(1, (expiresAt - Date.now()) / total)).toFixed(4));
      }
      if (remaining > 0) setTimeout(tick, 1000);
      else if (holder) holder.classList.add('dn-expired');
    }
    tick();
  });

  // Toasts.
  var ICONS = {
    ok: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="m8 12.5 3 3 5-6"/></svg>',
    error: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 7.5v5.5M12 16.5v.01"/></svg>',
    info: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 11v5.5M12 7.5v.01"/></svg>'
  };

  function toast(message, tone) {
    var host = document.getElementById('dnToasts');
    if (!host) return;
    tone = ICONS[tone] ? tone : 'info';
    var item = document.createElement('div');
    item.className = 'dn-toast dn-toast--' + tone;
    item.innerHTML = ICONS[tone];
    var text = document.createElement('span');
    text.textContent = message;
    item.appendChild(text);
    host.appendChild(item);
    while (host.children.length > 3) host.removeChild(host.firstElementChild);
    setTimeout(function () {
      item.classList.add('is-leaving');
      setTimeout(function () { item.remove(); }, 320);
    }, tone === 'error' ? 5200 : 3400);
  }

  window.DropNet = { toast: toast };
})();
