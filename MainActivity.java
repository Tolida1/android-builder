// ============================================================
// MainActivity.java
// Firestore'dan anlık config okur + FCM topic'e subscribe olur
// build_app.sh tarafından PACKAGE_NAME ile değiştirilerek
// doğru pakete yerleştirilir
// ============================================================
package PACKAGE_PLACEHOLDER;

import android.app.Activity;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.view.View;
import android.view.Window;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.ProgressBar;

import com.google.firebase.firestore.DocumentReference;
import com.google.firebase.firestore.FirebaseFirestore;
import com.google.firebase.firestore.ListenerRegistration;
import com.google.firebase.messaging.FirebaseMessaging;

public class MainActivity extends Activity {

    // Bu değerler build_app.sh tarafından doldurulur
    private static final String OWNER_ID   = "OWNER_ID_PLACEHOLDER";
    private static final String APP_ID     = "APP_ID_PLACEHOLDER";
    private static final String FCM_TOPIC  = "APP_TOPIC_PLACEHOLDER";   // "app_<appId>"
    private static final String DEFAULT_URL = "CONTENT_URL_PLACEHOLDER";

    private WebView        webView;
    private ProgressBar    progressBar;
    private FirebaseFirestore db;
    private ListenerRegistration configListener;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);

        // Layout: WebView + ProgressBar
        FrameLayout root = new FrameLayout(this);

        webView = new WebView(this);
        WebSettings ws = webView.getSettings();
        ws.setJavaScriptEnabled(true);
        ws.setDomStorageEnabled(true);
        ws.setLoadWithOverviewMode(true);
        ws.setUseWideViewPort(true);
        ws.setBuiltInZoomControls(false);
        ws.setDisplayZoomControls(false);
        ws.setCacheMode(WebSettings.LOAD_DEFAULT);

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView view, String url) {
                progressBar.setVisibility(View.GONE);
            }
        });

        progressBar = new ProgressBar(this, null,
                android.R.attr.progressBarStyleHorizontal);
        progressBar.setIndeterminate(true);
        progressBar.setVisibility(View.VISIBLE);

        FrameLayout.LayoutParams webParams = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT);

        FrameLayout.LayoutParams pbParams = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, 8);

        root.addView(webView, webParams);
        root.addView(progressBar, pbParams);
        setContentView(root);

        // Varsayılan URL'i yükle
        webView.loadUrl(DEFAULT_URL);

        // Firebase başlat
        db = FirebaseFirestore.getInstance();

        // FCM topic'e subscribe ol
        subscribeFCM();

        // Firestore'dan canlı config dinle
        listenConfig();
    }

    // ── FCM Subscribe ────────────────────────────────────────
    private void subscribeFCM() {
        FirebaseMessaging.getInstance()
            .subscribeToTopic(FCM_TOPIC)
            .addOnCompleteListener(task -> {
                // Sessizce başarılı/başarısız — kullanıcıya göstermiyoruz
            });
    }

    // ── Firestore Realtime Config ────────────────────────────
    private void listenConfig() {
        DocumentReference ref = db
            .collection("apps")
            .document(OWNER_ID)
            .collection("list")
            .document(APP_ID);

        configListener = ref.addSnapshotListener((snapshot, error) -> {
            if (error != null || snapshot == null || !snapshot.exists()) return;

            // Renkler
            String primary = snapshot.getString("config.primaryColor");
            if (primary != null) {
                try {
                    webView.setBackgroundColor(Color.parseColor(primary));
                    applyStatusBarColor(primary);
                } catch (IllegalArgumentException ignored) {}
            }

            // İçerik URL — sadece mevcut URL farklıysa yükle
            String url = snapshot.getString("config.contentUrl");
            if (url != null && !url.isEmpty()) {
                String current = webView.getUrl();
                if (current == null || !current.equals(url)) {
                    webView.loadUrl(url);
                    progressBar.setVisibility(View.VISIBLE);
                }
            }
        });
    }

    // ── Status Bar Rengi ─────────────────────────────────────
    private void applyStatusBarColor(String hexColor) {
        try {
            getWindow().setStatusBarColor(Color.parseColor(hexColor));
        } catch (Exception ignored) {}
    }

    // ── Geri Tuşu ────────────────────────────────────────────
    @Override
    public void onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }

    // ── Lifecycle ────────────────────────────────────────────
    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (configListener != null) {
            configListener.remove();
        }
    }
}
