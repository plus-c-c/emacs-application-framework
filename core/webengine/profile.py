#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from PyQt6.QtWebEngineCore import QWebEngineProfile, QWebEngineScript

webengine_profile = QWebEngineProfile('eaf')
webengine_profile.setPersistentCookiesPolicy(QWebEngineProfile.PersistentCookiesPolicy.ForcePersistentCookies)
webengine_profile.setHttpCacheType(QWebEngineProfile.HttpCacheType.DiskHttpCache)

# Inject prefers-color-scheme: dark override as a profile-level UserScript.
# Runs once at DocumentReady (before page scripts, after DOM ready) in MainWorld.
# Separated from dark_mode_js (DarkReader) which is injected on every progress < 100.
_dark_scheme_script = QWebEngineScript()
_dark_scheme_script.setName("eaf-dark-scheme")
_dark_scheme_script.setInjectionPoint(QWebEngineScript.InjectionPoint.DocumentReady)
_dark_scheme_script.setWorldId(QWebEngineScript.ScriptWorldId.MainWorld)
_dark_scheme_script.setRunsOnSubFrames(True)
_dark_scheme_script.setSourceCode("""
(function() {
    var orig = window.matchMedia;
    window.matchMedia = function(q) {
        var r = orig.call(window, q);
        if (q === '(prefers-color-scheme: dark)') {
            try { Object.defineProperty(r, 'matches', { get: function() { return true; } }); } catch(e) {}
        }
        return r;
    };
})();
""")
webengine_profile.scripts().insert(_dark_scheme_script)


