package com.kattes.mensch;

import android.app.Activity;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/**
 * Dünner WebView-Wrapper: lädt das Web-Spiel aus assets/index.html in einem
 * fullscreen WebView und reicht D-Pad-Events automatisch als
 * KeyboardEvents an die JavaScript-Schicht weiter. Die TV-Fernbedienungs-
 * Taste "Zurück" wird in onBackPressed() zuerst an die JS-Funktion
 * dpadBack() weitergeleitet (schließt Menü/Palette); kommt von dort
 * false zurück, beendet die Activity.
 */
public class MainActivity extends Activity {

    private WebView web;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        web = new WebView(this);
        web.setBackgroundColor(Color.parseColor("#3d2814")); // Holz-Fallback bis CSS lädt
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        // localStorage soll erhalten bleiben (Sound-On/Off, Sprachauswahl).
        s.setAllowFileAccess(true);
        s.setAllowContentAccess(true);
        // Damit Web Audio nicht erst auf einen pointerdown wartet – D-Pad
        // löst den Audio-Init in game.js mit aus.
        s.setMediaPlaybackRequiresUserGesture(false);
        // Skalierung deaktivieren; layoutTable() im Spiel passt sich selbst an.
        s.setLoadWithOverviewMode(false);
        s.setUseWideViewPort(false);

        web.setWebViewClient(new WebViewClient());

        // D-Pad-Events sollen im WebView landen, sonst kommen ArrowKeys nicht
        // bei JS an.
        web.setFocusable(true);
        web.setFocusableInTouchMode(true);

        setContentView(web);
        applyImmersive();
        web.requestFocus();
        web.loadUrl("file:///android_asset/index.html");
    }

    /** System-UI ausblenden (Fullscreen / Immersive Sticky). */
    private void applyImmersive() {
        View decor = getWindow().getDecorView();
        decor.setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                        | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            getWindow().getAttributes().layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
        }
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) applyImmersive();
    }

    @Override
    public void onBackPressed() {
        // Erst dem JS Gelegenheit geben, Menü/Palette zu schließen.
        web.evaluateJavascript(
                "(function(){ try { return (typeof dpadBack==='function') ? dpadBack() : false; } catch(e){ return false; } })()",
                value -> {
                    if (!"true".equals(value)) {
                        super.onBackPressed();
                    }
                });
    }

    @Override
    protected void onPause()  { super.onPause();  if (web != null) web.onPause();  }
    @Override
    protected void onResume() { super.onResume(); if (web != null) web.onResume(); }

    @Override
    protected void onDestroy() {
        if (web != null) {
            web.destroy();
            web = null;
        }
        super.onDestroy();
    }
}
