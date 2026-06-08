# WebView-JavaScriptInterface-Methoden vor R8 schützen (aktuell ungenutzt,
# aber als Vorlage hier hinterlegt). Release-Build hat minifyEnabled=false,
# daher reine Konvention.
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
