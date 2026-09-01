/// JS-injection ad blocker for the federated webview.
///
/// The federated `webview_flutter` API has no content-rule surface, so the
/// ad-blocker is ported to in-page JavaScript: the WebKit content-rule JSON
/// (already produced by `libublock`) is translated into a compact rule payload
/// and injected as a document-start script that hooks the page's network APIs
/// and hides cosmetic selectors.
///
/// This is weaker than native content filtering — it cannot intercept
/// subresources resolved purely by the engine before page scripts run, and it
/// only observes the request channels it hooks — but it preserves the same
/// data source (uBO's uAssets lists) and keeps the global blocked counter
/// working.
library;

import 'dart:convert';

/// Compiles a list of WebKit content-rule JSON documents (`parts`) into a
/// self-contained blocking script to inject at page start.
String jsBlockScript(List<String> parts) {
  final blocks = <List<dynamic>>[];
  final exceptions = <List<dynamic>>[];
  final cosmetics = <List<dynamic>>[];

  for (final part in parts) {
    List<dynamic> rules;
    try {
      rules = (jsonDecode(part) as List).cast<dynamic>();
    } catch (_) {
      continue;
    }
    for (final raw in rules) {
      if (raw is! Map) continue;
      final trigger = (raw['trigger'] as Map?)?.cast<String, dynamic>();
      final action = (raw['action'] as Map?)?.cast<String, dynamic>();
      if (trigger == null || action == null) continue;

      final urlFilter = trigger['url-filter'] as String? ?? '';
      final types = _stringList(trigger['resource-type']);
      final ifDomain = _stringList(trigger['if-domain']);
      final unlessDomain = _stringList(trigger['unless-domain']);
      final type = action['type'] as String? ?? '';

      switch (type) {
        case 'block':
          blocks.add([urlFilter, types, ifDomain, unlessDomain]);
          break;
        case 'ignore-previous-rules':
          exceptions.add([urlFilter, types, ifDomain, unlessDomain]);
          break;
        case 'css-display-none':
          final selector = (action['selector'] as String? ?? '').trim();
          if (selector.isNotEmpty) {
            // url-filter here is a page-domain regex (see convert.rs);
            // the header (optional trailing subdomain + the domain itself)
            // is all the injected CSS scoping needs.
            cosmetics.add([selector, urlFilter]);
          }
          break;
      }
    }
  }

  final payload = jsonEncode({'blocks': blocks, 'exceptions': exceptions});
  final css = jsonEncode(_cosmeticCss(cosmetics));
  return _blockerTemplate(payload, css);
}

String _blockerTemplate(String payloadJson, String cssJson) => '''
(function () {
  'use strict';
  if (window.__lumenAbInstalled) return;
  window.__lumenAbInstalled = true;
  var R = $payloadJson;
  var BLOCKS = [];
  var EX = [];
  (function () {
    var b = R.blocks || [], x = R.exceptions || [], i, eb, ed;
    for (i = 0; i < b.length; i++) {
      eb = b[i];
      BLOCKS.push([new RegExp(eb[0]), eb[1], eb[2], eb[3]]);
    }
    for (i = 0; i < x.length; i++) {
      ed = x[i];
      EX.push([new RegExp(ed[0]), ed[1], ed[2], ed[3]]);
    }
  })();
  var blockedCount = 0;

  function report(push) {
    if (!push) return;
    blockedCount += 1;
    if (window.webkit && window.webkit.messageHandlers &&
        window.webkit.messageHandlers.lumen_ab) {
      try {
        window.webkit.messageHandlers.lumen_ab.postMessage('1');
      } catch (e) {}
    }
  }

  function hostname(url) {
    try { return new URL(url).hostname.toLowerCase(); } catch (e) {
      var m = /([a-z0-9\\-]+\\.)*[a-z0-9\\-]+/i.exec(url);
      return m ? m[0].toLowerCase() : '';
    }
  }

  function domainsOk(ifD, unlessD, host) {
    if (ifD && ifD.length) {
      var hit = false;
      for (var i = 0; i < ifD.length; i++) {
        if (host === ifD[i] || host.endsWith('.' + ifD[i])) { hit = true; break; }
      }
      if (!hit) return false;
    }
    if (unlessD && unlessD.length) {
      for (var j = 0; j < unlessD.length; j++) {
        if (host === unlessD[j] || host.endsWith('.' + unlessD[j])) return false;
      }
    }
    return true;
  }

  function typesOk(types, t) {
    return !types || !types.length || types.indexOf(t) !== -1;
  }

  function isBlocked(url, type) {
    var host = hostname(url);
    var i;
    // exceptions override blocks
    for (i = 0; i < EX.length; i++) {
      if (EX[i][0].test(url) && typesOk(EX[i][1], type) && domainsOk(EX[i][2], EX[i][3], host)) {
        return false;
      }
    }
    for (i = 0; i < BLOCKS.length; i++) {
      if (BLOCKS[i][0].test(url) && typesOk(BLOCKS[i][1], type) && domainsOk(BLOCKS[i][2], BLOCKS[i][3], host)) {
        return true;
      }
    }
    return false;
  }

  // fetch
  var _fetch = window.fetch;
  if (typeof _fetch === 'function') {
    window.fetch = function (input, init) {
      var url = typeof input === 'string' ? input : (input && input.url) || '';
      if (url && isBlocked(url, 'fetch')) {
        report(true);
        return Promise.reject(new TypeError('Failed to fetch'));
      }
      return _fetch.apply(this, arguments);
    };
  }

  // XMLHttpRequest
  var _xhrOpen = XMLHttpRequest.prototype.open;
  var _xhrSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url) {
    this.__abUrl = url || '';
    return _xhrOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function () {
    if (this.__abUrl && isBlocked(this.__abUrl, 'raw')) {
      report(true);
      try { this.abort(); } catch (e) {}
      return;
    }
    return _xhrSend.apply(this, arguments);
  };

  // sendBeacon
  if (navigator.sendBeacon) {
    var _beacon = navigator.sendBeacon;
    navigator.sendBeacon = function (url) {
      if (isBlocked(url, 'raw')) { report(true); return false; }
      return _beacon.apply(this, arguments);
    };
  }

  // window.open (popup)
  var _open = window.open;
  window.open = function (url) {
    if (url && isBlocked(url, 'popup')) {
      report(true);
      return null;
    }
    return _open.apply(this, arguments);
  };

  // cosmetic hiding
  try {
    var css = $cssJson;
    var styleRules = [];
    for (var c2 = 0; c2 < css.length; c2++) {
      var skin = css[c2];
      if ((new RegExp(skin.re)).test(location.href)) {
        styleRules.push(skin.selectors + '{display:none !important;}');
      }
    }
    if (styleRules.length) {
      var st = document.createElement('style');
      st.setAttribute('type', 'text/css');
      st.textContent = styleRules.join('\\n');
      (document.head || document.documentElement).appendChild(st);
    }
  } catch (e) {}
})();
''';

/// Groups cosmetic selectors by their page-domain regex so the injected script
/// hides them only on pages whose URL matches (mirroring WebKit's css
/// matching, including subdomains/ports and bare `.*` globals).
List<Map<String, dynamic>> _cosmeticCss(List<List<dynamic>> cosmetics) {
  final byRe = <String, List<String>>{};
  for (final c in cosmetics) {
    final selector = c[0] as String;
    final re = c[1] as String;
    if (selector.isEmpty) continue;
    byRe.putIfAbsent(re, () => []).add(selector);
  }
  return [
    for (final e in byRe.entries)
      {'re': e.key, 'selectors': e.value.join(',')},
  ];
}

List<String> _stringList(Object? v) {
  if (v == null) return const [];
  if (v is List) {
    return [for (final e in v) e as String? ?? ''];
  }
  if (v is String) return [v];
  return const [];
}
