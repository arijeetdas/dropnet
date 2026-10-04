import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import '../../widgets/platform_logo.dart';
import '../platform/device_environment.dart';

/// Shared look and feel of the pages DropNet serves to browsers (the Web
/// Portal and the Temporary Share): brand assets, page chrome and the PIN
/// gate. Presentation only: nothing here reads or changes transfer state.
class WebPortalKit {
  WebPortalKit._();

  /// URL prefix of the static brand assets, served by both web servers.
  static const String assetBase = '/_dropnet';
  static const String officialSite = 'https://dropnet.arijeet.in';
  static const String officialSource = 'https://git-dropnet.arijeet.in';

  static const String _iconAsset = 'assets/icon/app_icon.png';
  static const int _iconSize = 192;

  static final HtmlEscape _escape = const HtmlEscape();
  static String esc(String value) => _escape.convert(value);

  // ---------------------------------------------------------------------------
  // Host facts shown on every page: app name, version (no build number) and
  // the platform the host app runs on.

  static String? _cachedVersion;

  /// `2.5.3` from `version: 2.5.3+27` in the bundled pubspec.yaml.
  static Future<String> versionName() async {
    if (_cachedVersion != null) return _cachedVersion!;
    try {
      final pubspec = await rootBundle.loadString('pubspec.yaml');
      final match = RegExp(r'^version:\s*([^+\s]+)', multiLine: true).firstMatch(pubspec);
      if (match != null) return _cachedVersion = match.group(1)!;
    } catch (_) {}
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.trim().isNotEmpty) return _cachedVersion = info.version.trim();
    } catch (_) {}
    return '';
  }

  static String get platformName => DeviceEnvironment.platformDisplayName;

  /// The iOS logo is a single black shape and must be tinted per theme.
  static bool get _platformLogoIsMono => platformName == 'iOS';

  static String _v(String version) => Uri.encodeQueryComponent(version.isEmpty ? '0' : version);

  static String iconUrl(String version) => '$assetBase/icon.png?v=${_v(version)}';

  /// `<img>` of the host platform's logo (the same SVG the app shows).
  static String platformLogo(String version, {String className = 'dn-platform-logo'}) {
    if (PlatformLogo.currentAssetPath() == null) return '';
    return '<img class="$className" src="$assetBase/platform.svg?v=${_v(version)}" alt="${esc(platformName)}" '
        'height="18" decoding="async" onerror="this.remove()" />';
  }

  // ---------------------------------------------------------------------------
  // Static assets.

  static Future<Uint8List>? _icon;

  /// Serves `/_dropnet/<name>`. Public on purpose: these are the same files
  /// that ship inside every app build.
  static Future<Response> serveAsset(String name) async {
    const cache = 'public, max-age=86400';
    try {
      switch (name) {
        case 'dropnet.css':
          return Response.ok(
            await rootBundle.loadString('assets/web/dropnet.css'),
            headers: {'content-type': 'text/css; charset=utf-8', 'cache-control': cache},
          );
        case 'dropnet.js':
          return Response.ok(
            await rootBundle.loadString('assets/web/dropnet.js'),
            headers: {'content-type': 'text/javascript; charset=utf-8', 'cache-control': cache},
          );
        case 'icon.png':
          return Response.ok(
            await (_icon ??= _loadIcon()),
            headers: {'content-type': 'image/png', 'cache-control': cache},
          );
        case 'platform.svg':
          final path = PlatformLogo.currentAssetPath();
          if (path == null) return Response.notFound('Not found');
          return Response.ok(
            await rootBundle.loadString(path),
            headers: {'content-type': 'image/svg+xml; charset=utf-8', 'cache-control': cache},
          );
      }
    } catch (_) {
      if (name == 'icon.png') _icon = null;
    }
    return Response.notFound('Not found');
  }

  /// The app icon downscaled once (the source PNG is >1 MB), falling back to
  /// the original bytes if decoding is unavailable.
  static Future<Uint8List> _loadIcon() async {
    final data = await rootBundle.load(_iconAsset);
    final original = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    try {
      final codec = await ui.instantiateImageCodec(
        original,
        targetWidth: _iconSize,
        targetHeight: _iconSize,
      );
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      if (png != null) return png.buffer.asUint8List();
    } catch (_) {}
    return original;
  }

  // ---------------------------------------------------------------------------
  // Page chrome.

  /// Everything inside `<head>` except page specific scripts.
  static String head({required String title, required String version}) {
    final v = _v(version);
    final monoStyle = _platformLogoIsMono
        ? '<style>.dn-platform-logo{filter:var(--mono-logo-filter)}</style>'
        : '';
    return '''
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
  <meta name="color-scheme" content="light dark" />
  <meta name="description" content="DropNet: private file sharing across your local network." />
  <meta name="theme-color" content="#f3f7f4" media="(prefers-color-scheme: light)" />
  <meta name="theme-color" content="#060d0a" media="(prefers-color-scheme: dark)" />
  <title>${esc(title)}</title>
  <link rel="icon" type="image/png" href="$assetBase/icon.png?v=$v" />
  <link rel="apple-touch-icon" href="$assetBase/icon.png?v=$v" />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&amp;display=swap" media="print" onload="this.media='all'" />
  <link rel="stylesheet" href="$assetBase/dropnet.css?v=$v" />
  <script>(function(){try{var t=localStorage.getItem('dropnet-theme');if(t==='light'||t==='dark'){document.documentElement.setAttribute('data-theme',t);}}catch(e){}})();</script>
  $monoStyle''';
  }

  /// Animated background layer, placed first in `<body>`.
  static const String backdrop =
      '<div class="dn-backdrop" aria-hidden="true"><span></span><span></span></div>';

  static String header({required String version, required String section}) {
    final v = _v(version);
    final versionChip = version.isEmpty ? '' : '<span class="dn-host-version">v${esc(version)}</span>';
    return '''
<header class="dn-nav">
  <div class="dn-nav-inner">
    <a class="dn-brand" href="$officialSite" target="_blank" rel="noopener noreferrer" aria-label="DropNet website (opens in a new tab)">
      <img class="dn-brand-logo" src="$assetBase/icon.png?v=$v" alt="" width="36" height="36" />
      <span class="dn-brand-text"><span class="dn-brand-name">DropNet</span><span class="dn-brand-section">${esc(section)}</span></span>
    </a>
    <div class="dn-nav-actions">
      <span class="dn-host-chip" title="Hosted by DropNet for ${esc(platformName)}">
        ${platformLogo(version)}<span class="dn-host-name">DropNet for ${esc(platformName)}</span>$versionChip
      </span>
      <button class="dn-icon-btn dn-theme-toggle" type="button" data-theme-toggle aria-label="Switch between light and dark theme" title="Switch theme">$_sunSvg$_moonSvg</button>
    </div>
  </div>
</header>''';
  }

  /// Footer plus the shared script. Place right before the page's own script.
  static String footer({required String version}) {
    final v = _v(version);
    final versionText = version.isEmpty ? '' : ' <span class="dn-dot-sep">·</span> v${esc(version)}';
    return '''
<footer class="dn-footer">
  <div class="dn-footer-inner">
    <div class="dn-footer-brand">
      <img class="dn-footer-logo" src="$assetBase/icon.png?v=$v" alt="" width="40" height="40" loading="lazy" />
      <div class="dn-footer-copy">
        <strong>DropNet</strong>
        <span class="dn-footer-host">${platformLogo(version)}DropNet for ${esc(platformName)}$versionText</span>
      </div>
    </div>
    <nav class="dn-footer-links" aria-label="Official DropNet pages">
      <a href="$officialSite" target="_blank" rel="noopener noreferrer">$_downloadSvg<span>Get DropNet</span></a>
      <a href="$officialSource" target="_blank" rel="noopener noreferrer">$_githubSvg<span>Source code</span></a>
    </nav>
  </div>
</footer>
<div class="dn-toasts" id="dnToasts" role="status" aria-live="polite"></div>
<script src="$assetBase/dropnet.js?v=$v"></script>''';
  }

  /// The DropNet icon with radar rings rippling out of it.
  static String orb(String version, {String size = 'md', String badge = ''}) {
    final badgeHtml = badge.isEmpty ? '' : '<span class="dn-orb-badge">$badge</span>';
    return '<div class="dn-orb dn-orb--$size" aria-hidden="true">'
        '<span class="dn-orb-ring"></span><span class="dn-orb-ring"></span><span class="dn-orb-ring"></span>'
        '<img class="dn-orb-logo" src="$assetBase/icon.png?v=${_v(version)}" alt="" />$badgeHtml</div>';
  }

  /// PIN gate shared by both servers. The form contract (POST [action] with a
  /// `pin` field) is unchanged.
  static String renderPinGate({
    required String version,
    required String section,
    required String action,
    required String message,
    bool error = false,
  }) {
    final errorHtml = error
        ? '<p class="dn-alert dn-alert--error" role="alert">$_alertSvg<span>Incorrect PIN. Please try again.</span></p>'
        : '';
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
${head(title: 'DropNet · PIN required', version: version)}
</head>
<body class="dn-page">
  $backdrop
  ${header(version: version, section: section)}
  <main class="dn-main dn-gate">
    <section class="dn-card dn-gate-card dn-rise${error ? ' dn-shake' : ''}">
      ${orb(version, size: 'sm', badge: _lockSvg)}
      <p class="dn-eyebrow">Protected</p>
      <h1 class="dn-title">PIN required</h1>
      <p class="dn-lead">${esc(message)}</p>
      <form method="POST" action="$action" class="dn-gate-form">
        <label class="dn-label" for="pin">PIN</label>
        <div class="dn-pin-field">
          <input class="dn-input dn-input--pin" type="password" id="pin" name="pin" autocomplete="one-time-code" autocapitalize="off" autocorrect="off" spellcheck="false" autofocus required />
          <button type="button" class="dn-pin-reveal" data-pin-reveal aria-label="Show PIN" title="Show PIN">$_eyeSvg</button>
        </div>
        $errorHtml
        <button type="submit" class="dn-btn dn-btn--primary dn-btn--block dn-btn--lg">Unlock$_arrowSvg</button>
      </form>
      <p class="dn-fine">Ask the person sharing for the PIN shown in their DropNet app.</p>
    </section>
  </main>
  ${footer(version: version)}
</body>
</html>
''';
  }

  // ---------------------------------------------------------------------------
  // File presentation (kept in sync with `fileKind` in assets/web/index.html).

  static String fileKind(String name) {
    final ext = p.extension(name).toLowerCase();
    if ({'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg', '.heic', '.heif'}.contains(ext)) return 'image';
    if ({'.mp4', '.mov', '.mkv', '.avi', '.webm', '.m4v', '.3gp'}.contains(ext)) return 'video';
    if ({'.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.opus'}.contains(ext)) return 'audio';
    if (ext == '.pdf') return 'pdf';
    if ({'.doc', '.docx', '.odt', '.rtf'}.contains(ext)) return 'doc';
    if ({'.xls', '.xlsx', '.csv', '.ods'}.contains(ext)) return 'sheet';
    if ({'.ppt', '.pptx', '.odp'}.contains(ext)) return 'slides';
    if ({'.txt', '.md', '.json', '.xml', '.yaml', '.yml', '.ini', '.log'}.contains(ext)) return 'text';
    if ({'.dart', '.js', '.ts', '.tsx', '.jsx', '.py', '.java', '.kt', '.cpp', '.c', '.h', '.hpp', '.cs', '.php', '.go', '.rs', '.swift', '.html', '.css', '.scss', '.sql', '.sh', '.bat', '.ps1'}.contains(ext)) return 'code';
    if ({'.zip', '.rar', '.7z', '.tar', '.gz'}.contains(ext)) return 'archive';
    if ({'.apk', '.aab', '.apks', '.xapk', '.exe', '.msi', '.msix', '.dmg', '.pkg', '.deb', '.rpm', '.appimage', '.ipa'}.contains(ext)) return 'app';
    return 'file';
  }

  static String fileIcon(String kind) {
    final body = switch (kind) {
      'image' => '<rect x="3" y="3" width="18" height="18" rx="4"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.1-3.1a2 2 0 0 0-2.8 0L6 21"/>',
      'video' => '<rect x="2.5" y="6" width="13" height="12" rx="3"/><path d="m15.5 10.5 6-3.5v10l-6-3.5"/>',
      'audio' => '<path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>',
      'pdf' || 'doc' || 'text' => '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5M9 13h6M9 17h4"/>',
      'sheet' => '<rect x="3" y="3" width="18" height="18" rx="3"/><path d="M3 9h18M3 15h18M9 3v18"/>',
      'slides' => '<rect x="3" y="4" width="18" height="12" rx="2.5"/><path d="M12 16v4M8 20h8"/>',
      'code' => '<path d="m8 8-4 4 4 4M16 8l4 4-4 4M13.5 5l-3 14"/>',
      'archive' => '<rect x="3" y="4" width="18" height="5" rx="1.5"/><path d="M5 9v9a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V9M10 13h4"/>',
      'app' => '<rect x="6" y="2.5" width="12" height="19" rx="3"/><path d="M11 18h2"/>',
      _ => '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>',
    };
    return '<svg viewBox="0 0 24 24" aria-hidden="true">$body</svg>';
  }

  // ---------------------------------------------------------------------------
  // Icons.

  static const String downloadSvg =
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 4v11m0 0-4.5-4.5M12 15l4.5-4.5M5 20h14"/></svg>';
  static const String checkSvg =
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 12.5 4.5 4.5L19 7.5"/></svg>';
  static const String shieldSvg =
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3 5 6v5c0 4.4 3 8.3 7 9.5 4-1.2 7-5.1 7-9.5V6z"/><path d="m9 12 2 2 4-4"/></svg>';
  static const String _downloadSvg = downloadSvg;
  static const String _lockSvg =
      '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="5" y="10.5" width="14" height="10" rx="2.5"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5"/></svg>';
  static const String _eyeSvg =
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/></svg>';
  static const String _arrowSvg =
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14m-5-5 5 5-5 5"/></svg>';
  static const String _alertSvg =
      '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 7.5v5.5M12 16.5v.01"/></svg>';
  static const String _sunSvg =
      '<svg class="dn-sun" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2.5v2M12 19.5v2M4.6 4.6l1.4 1.4M18 18l1.4 1.4M2.5 12h2M19.5 12h2M4.6 19.4 6 18M18 6l1.4-1.4"/></svg>';
  static const String _moonSvg =
      '<svg class="dn-moon" viewBox="0 0 24 24" aria-hidden="true"><path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/></svg>';
  static const String _githubSvg =
      '<svg class="dn-fill" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"/></svg>';
}
