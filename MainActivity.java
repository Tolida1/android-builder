package PACKAGE_PLACEHOLDER;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;
import androidx.recyclerview.widget.GridLayoutManager;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.google.firebase.firestore.FirebaseFirestore;
import com.google.firebase.firestore.ListenerRegistration;
import com.google.firebase.messaging.FirebaseMessaging;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public class MainActivity extends Activity {

    static final String OWNER_ID    = "OWNER_ID_PLACEHOLDER";
    static final String APP_ID      = "APP_ID_PLACEHOLDER";
    static final String FCM_TOPIC   = "APP_TOPIC_PLACEHOLDER";
    static final String DEFAULT_URL = "CONTENT_URL_PLACEHOLDER";

    private FrameLayout   rootLayout;
    private WebView       webView;
    private ProgressBar   progressBar;
    private RecyclerView  contentRecycler;
    private LinearLayout  bottomNav;

    private FirebaseFirestore    db;
    private ListenerRegistration configListener;

    // Tüm bölümler (aktif+pasif)
    private final List<Map<String,Object>> allSections    = new ArrayList<>();
    // Sadece aktif bölümler — bottom nav için
    private final List<Map<String,Object>> activeSections = new ArrayList<>();

    private int    activeNavIndex = -1;
    private String primaryColor   = "#6c63ff";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(
            WindowManager.LayoutParams.FLAG_FULLSCREEN,
            WindowManager.LayoutParams.FLAG_FULLSCREEN);
        buildLayout();
        FirebaseMessaging.getInstance().subscribeToTopic(FCM_TOPIC);
        db = FirebaseFirestore.getInstance();
        listenConfig();
    }

    // ── Layout ────────────────────────────────────────────────
    private void buildLayout() {
        rootLayout = new FrameLayout(this);
        rootLayout.setBackgroundColor(Color.BLACK);

        webView = new WebView(this);
        WebSettings ws = webView.getSettings();
        ws.setJavaScriptEnabled(true);
        ws.setDomStorageEnabled(true);
        ws.setLoadWithOverviewMode(true);
        ws.setUseWideViewPort(true);
        ws.setBuiltInZoomControls(false);
        ws.setMediaPlaybackRequiresUserGesture(false);
        ws.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        ws.setUserAgentString("Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/110.0.0.0 Mobile Safari/537.36");
        webView.setWebViewClient(new WebViewClient() {
            @Override public void onPageFinished(WebView v, String u) {
                progressBar.setVisibility(View.GONE);
            }
        });
        webView.loadUrl(DEFAULT_URL);

        contentRecycler = new RecyclerView(this);
        contentRecycler.setVisibility(View.GONE);
        contentRecycler.setBackgroundColor(Color.parseColor("#080812"));

        progressBar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        progressBar.setIndeterminate(true);

        bottomNav = new LinearLayout(this);
        bottomNav.setOrientation(LinearLayout.HORIZONTAL);
        bottomNav.setBackgroundColor(Color.parseColor("#0f0f1a"));
        bottomNav.setVisibility(View.GONE);

        FrameLayout.LayoutParams fill = new FrameLayout.LayoutParams(-1, -1);
        FrameLayout.LayoutParams pb   = new FrameLayout.LayoutParams(-1, dp(4));
        FrameLayout.LayoutParams nav  = new FrameLayout.LayoutParams(-1, dp(58));
        nav.gravity = Gravity.BOTTOM;

        rootLayout.addView(webView, fill);
        rootLayout.addView(contentRecycler, fill);
        rootLayout.addView(progressBar, pb);
        rootLayout.addView(bottomNav, nav);
        setContentView(rootLayout);
    }

    // ── Firestore Config ──────────────────────────────────────
    @SuppressWarnings("unchecked")
    private void listenConfig() {
        configListener = db.collection("apps").document(OWNER_ID)
            .collection("list").document(APP_ID)
            .addSnapshotListener((snap, err) -> {
                if (err != null || snap == null || !snap.exists()) return;

                // Primary color
                String pc = snap.getString("config.primaryColor");
                if (pc != null && !pc.isEmpty()) primaryColor = pc;
                try { getWindow().setStatusBarColor(Color.parseColor(primaryColor)); }
                catch (Exception ignored) {}

                // Menu sections
                allSections.clear();
                activeSections.clear();
                List<Object> raw = (List<Object>) snap.get("config.menu");
                if (raw != null) {
                    for (Object o : raw) {
                        if (!(o instanceof Map)) continue;
                        Map<String,Object> s = (Map<String,Object>) o;
                        allSections.add(s);
                        // Aktif kontrolü (active field yoksa varsayılan true)
                        Object activeObj = s.get("active");
                        boolean isActive = !(Boolean.FALSE.equals(activeObj));
                        if (isActive) activeSections.add(s);
                    }
                }

                runOnUiThread(() -> {
                    buildBottomNav();
                    if (activeNavIndex < 0 && !activeSections.isEmpty()) {
                        selectSection(0);
                    } else if (activeSections.isEmpty()) {
                        String url = snap.getString("config.contentUrl");
                        showWebView(url != null ? url : DEFAULT_URL);
                    } else if (activeNavIndex >= 0 && activeNavIndex < activeSections.size()) {
                        // Config değişti, mevcut bölümü yenile
                        selectSection(activeNavIndex);
                    }
                });
            });
    }

    // ── Bottom Nav (sadece aktif bölümler) ────────────────────
    private void buildBottomNav() {
        bottomNav.removeAllViews();
        if (activeSections.isEmpty()) { bottomNav.setVisibility(View.GONE); return; }
        // Tek bölüm varsa nav gizle
        if (activeSections.size() == 1) { bottomNav.setVisibility(View.GONE); return; }
        bottomNav.setVisibility(View.VISIBLE);

        int activeColor;
        try { activeColor = Color.parseColor(primaryColor); }
        catch (Exception e) { activeColor = Color.parseColor("#6c63ff"); }
        int inactiveColor = Color.parseColor("#606080");

        for (int i = 0; i < activeSections.size(); i++) {
            final int idx = i;
            Map<String,Object> s = activeSections.get(i);
            String title = strOr(s, "title", "");
            String icon  = strOr(s, "icon",  "▶");
            boolean isSel = (idx == activeNavIndex);

            LinearLayout item = new LinearLayout(this);
            item.setOrientation(LinearLayout.VERTICAL);
            item.setGravity(Gravity.CENTER);
            item.setLayoutParams(new LinearLayout.LayoutParams(0, -1, 1f));
            if (isSel) item.setBackgroundColor(Color.parseColor("#1a1a2e"));
            item.setOnClickListener(v -> selectSection(idx));

            TextView iv = new TextView(this);
            iv.setText(icon.isEmpty() ? "▶" : icon);
            iv.setTextSize(18); iv.setGravity(Gravity.CENTER);
            iv.setTextColor(isSel ? activeColor : inactiveColor);

            TextView tv = new TextView(this);
            tv.setText(title);
            tv.setTextSize(9); tv.setGravity(Gravity.CENTER);
            tv.setTextColor(isSel ? activeColor : inactiveColor);

            item.addView(iv); item.addView(tv);
            bottomNav.addView(item);
        }
    }

    // ── Select Section ────────────────────────────────────────
    @SuppressWarnings("unchecked")
    private void selectSection(int idx) {
        if (idx >= activeSections.size()) return;
        activeNavIndex = idx;
        buildBottomNav();
        Map<String,Object> section = activeSections.get(idx);
        String type    = strOr(section, "type",    "web");
        String display = strOr(section, "display", "list");
        String url     = strOr(section, "url",     "");

        if ("m3u".equals(type) || "iptv".equals(type)) {
            // Aktif içerikleri filtrele
            List<Object> rawItems = (List<Object>) section.get("items");
            List<Map<String,Object>> activeItems = new ArrayList<>();
            if (rawItems != null) {
                for (Object o : rawItems) {
                    if (!(o instanceof Map)) continue;
                    Map<String,Object> item = (Map<String,Object>) o;
                    Object activeObj = item.get("active");
                    boolean isActive = !(Boolean.FALSE.equals(activeObj));
                    if (isActive) activeItems.add(item);
                }
            }

            if ("single".equals(display)) {
                // Tekli mod: sadece bir içerik varsa direkt aç
                if (activeItems.size() == 1) {
                    Map<String,Object> item = activeItems.get(0);
                    openPlayer(strOr(item,"url",""), strOr(item,"name",""),
                               strOr(item,"referer",""), strOr(item,"origin",""));
                } else if (activeItems.size() > 1) {
                    // Birden fazla varsa liste göster
                    showContentList(activeItems, "list");
                } else if (!url.isEmpty()) {
                    // items boşsa M3U URL'den yükle
                    loadM3uFromUrl(url, section, display);
                }
            } else {
                if (!activeItems.isEmpty()) {
                    showContentList(activeItems, display);
                } else if (!url.isEmpty()) {
                    // items yoksa M3U URL'den parse et
                    loadM3uFromUrl(url, section, display);
                } else {
                    Toast.makeText(this, "İçerik bulunamadı", Toast.LENGTH_SHORT).show();
                }
            }
        } else if ("video".equals(type)) {
            String referer = strOr(section, "referer", "");
            String origin  = strOr(section, "origin",  "");
            openPlayer(url, strOr(section, "title", ""), referer, origin);
        } else {
            // Web
            showWebView(url);
        }
    }

    // ── M3U URL'den parse et (arka planda) ───────────────────
    private void loadM3uFromUrl(String m3uUrl, Map<String,Object> section, String display) {
        progressBar.setVisibility(View.VISIBLE);
        webView.setVisibility(View.GONE);
        contentRecycler.setVisibility(View.GONE);

        new Thread(new Runnable() {
            @Override public void run() {
                try {
                    List<M3uParser.Channel> channels = M3uParser.parseFromUrl(m3uUrl);
                    List<Map<String,Object>> items = new ArrayList<>();
                    for (M3uParser.Channel ch : channels) {
                        items.add(ch.toMap());
                    }
                    runOnUiThread(() -> {
                        progressBar.setVisibility(View.GONE);
                        if (items.isEmpty()) {
                            Toast.makeText(MainActivity.this, "Liste boş", Toast.LENGTH_SHORT).show();
                        } else if ("single".equals(display) && items.size() == 1) {
                            Map<String,Object> item = items.get(0);
                            openPlayer(strOr(item,"url",""), strOr(item,"name",""),
                                       strOr(item,"referer",""), strOr(item,"origin",""));
                        } else {
                            showContentList(items, display);
                        }
                    });
                } catch (Exception e) {
                    runOnUiThread(() -> {
                        progressBar.setVisibility(View.GONE);
                        Toast.makeText(MainActivity.this,
                            "M3U yüklenemedi: " + e.getMessage(), Toast.LENGTH_LONG).show();
                    });
                }
            }
        }).start();
    }

    // ── Show WebView ──────────────────────────────────────────
    private void showWebView(String url) {
        webView.setVisibility(View.VISIBLE);
        contentRecycler.setVisibility(View.GONE);
        if (url != null && !url.isEmpty() && !url.equals(webView.getUrl())) {
            progressBar.setVisibility(View.VISIBLE);
            webView.loadUrl(url);
        }
    }

    // ── Show Content List ─────────────────────────────────────
    private void showContentList(List<Map<String,Object>> items, String display) {
        webView.setVisibility(View.GONE);
        contentRecycler.setVisibility(View.VISIBLE);
        if ("grid".equals(display)) {
            contentRecycler.setLayoutManager(new GridLayoutManager(this, 3));
        } else {
            contentRecycler.setLayoutManager(new LinearLayoutManager(this));
        }
        contentRecycler.setAdapter(new ContentAdapter(this, items, display, primaryColor,
            item -> openPlayer(
                strOr(item, "url",     ""),
                strOr(item, "name",    ""),
                strOr(item, "referer", ""),
                strOr(item, "origin",  "")
            )));
    }

    // ── Open Player ───────────────────────────────────────────
    void openPlayer(String url, String title, String referer, String origin) {
        if (url == null || url.isEmpty()) {
            Toast.makeText(this, "URL bulunamadı", Toast.LENGTH_SHORT).show();
            return;
        }
        Intent i = new Intent(this, PlayerActivity.class);
        i.putExtra("url",     url);
        i.putExtra("title",   title   != null ? title   : "");
        i.putExtra("referer", referer != null ? referer : "");
        i.putExtra("origin",  origin  != null ? origin  : "");
        startActivity(i);
    }

    // ── Helpers ───────────────────────────────────────────────
    static String strOr(Map<String,Object> m, String k, String def) {
        Object v = m.get(k);
        return (v instanceof String && !((String)v).isEmpty()) ? (String)v : def;
    }
    int dp(int v) { return Math.round(v * getResources().getDisplayMetrics().density); }

    @Override public void onBackPressed() {
        if (webView.getVisibility() == View.VISIBLE && webView.canGoBack()) webView.goBack();
        else super.onBackPressed();
    }
    @Override protected void onDestroy() {
        super.onDestroy();
        if (configListener != null) configListener.remove();
    }
}
