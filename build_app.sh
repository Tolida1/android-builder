#!/bin/bash
set -e
echo "=== BUILD: $APP_NAME / $PACKAGE_NAME ==="

# SDK
ANDROID_SDK="${ANDROID_HOME:-/usr/local/lib/android/sdk}"
BUILD_TOOLS=$(ls -d "$ANDROID_SDK/build-tools/"* 2>/dev/null | sort -V | tail -1)
export PATH="$BUILD_TOOLS:$ANDROID_SDK/platform-tools:$PATH"
echo "Build tools: $BUILD_TOOLS"

# Gradle 7.6.4
GV="7.6.4"
GRADLE="/opt/gradle-${GV}/bin/gradle"
if [ ! -f "$GRADLE" ]; then
  wget -q "https://services.gradle.org/distributions/gradle-${GV}-bin.zip" -O /tmp/g.zip
  sudo unzip -q /tmp/g.zip -d /opt/ && rm -f /tmp/g.zip
fi

# Workspace
WS="/tmp/build_${APP_ID}_$$"
rm -rf "$WS" && mkdir -p "$WS" && cd "$WS"
PKG_PATH=$(echo "$PACKAGE_NAME" | tr '.' '/')
mkdir -p app/src/main/java/$PKG_PATH
mkdir -p app/src/main/res/{values,mipmap-hdpi,mipmap-mdpi,mipmap-xhdpi,mipmap-xxhdpi,mipmap-xxxhdpi}

# google-services.json
echo "$GOOGLE_SERVICES_JSON" > app/google-services.json
python3 -c "
import json
with open('app/google-services.json') as f: d=json.load(f)
for c in d.get('client',[]): c['client_info']['android_client_info']['package_name']='${PACKAGE_NAME}'
with open('app/google-services.json','w') as f: json.dump(d,f,indent=2)
print('gsj patched')
"

# ── Java dosyaları (gömülü) ─────────────────────────────

cat > "app/src/main/java/$PKG_PATH/MainActivity.java" << 'JAVA_MAINACTIVITY_EOF'
package PACKAGE_PLACEHOLDER;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
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
import android.widget.FrameLayout;
import com.google.firebase.firestore.FirebaseFirestore;
import com.google.firebase.firestore.ListenerRegistration;
import com.google.firebase.messaging.FirebaseMessaging;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class MainActivity extends Activity {

    static final String OWNER_ID    = "OWNER_ID_PLACEHOLDER";
    static final String APP_ID      = "APP_ID_PLACEHOLDER";
    static final String FCM_TOPIC   = "APP_TOPIC_PLACEHOLDER";
    static final String DEFAULT_URL = "CONTENT_URL_PLACEHOLDER";

    // ── Views ─────────────────────────────────────────────────
    private FrameLayout  root;
    private WebView      webView;
    private ProgressBar  progress;
    private RecyclerView recycler;
    private LinearLayout bottomNav;

    // ── State ─────────────────────────────────────────────────
    private FirebaseFirestore    db;
    private ListenerRegistration listener;
    private String primaryColor = "#1a1a2e";

    // Aktif nav öğeleri (her biri bir "tab")
    private final List<Map<String,Object>> navTabs = new ArrayList<>();
    private int activeTab = -1;
    private AdManager adManager;
    private FrameLayout bannerContainer;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(
            WindowManager.LayoutParams.FLAG_FULLSCREEN,
            WindowManager.LayoutParams.FLAG_FULLSCREEN);
        buildUI();
        FirebaseMessaging.getInstance().subscribeToTopic(FCM_TOPIC);
        db = FirebaseFirestore.getInstance();
        adManager = new AdManager(this);
        startListening();
    }

    // ── Build UI ──────────────────────────────────────────────
    private void buildUI() {
        root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);

        // WebView
        webView = new WebView(this);
        WebSettings s = webView.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        s.setBuiltInZoomControls(false);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        s.setUserAgentString("Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/110.0.0.0 Mobile Safari/537.36");
        webView.setWebViewClient(new WebViewClient() {
            @Override public void onPageFinished(WebView v, String u) {
                progress.setVisibility(View.GONE);
            }
        });
        webView.loadUrl(DEFAULT_URL);

        // RecyclerView (kanal listesi için)
        recycler = new RecyclerView(this);
        recycler.setVisibility(View.GONE);
        recycler.setBackgroundColor(Color.parseColor("#08080f"));

        // Progress
        progress = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        progress.setIndeterminate(true);

        // Bottom nav
        bottomNav = new LinearLayout(this);
        bottomNav.setOrientation(LinearLayout.HORIZONTAL);
        bottomNav.setBackgroundColor(Color.parseColor("#0f0f1a"));
        bottomNav.setVisibility(View.GONE);

        FrameLayout.LayoutParams fill = new FrameLayout.LayoutParams(-1, -1);
        FrameLayout.LayoutParams pb   = new FrameLayout.LayoutParams(-1, dp(4));
        FrameLayout.LayoutParams nav  = new FrameLayout.LayoutParams(-1, dp(56));
        nav.gravity = Gravity.BOTTOM;

        // Banner container (reklamlar için - nav'ın üstüne gelir)
        bannerContainer = new FrameLayout(this);
        FrameLayout.LayoutParams bcParams = new FrameLayout.LayoutParams(-1, -2);
        bcParams.gravity = Gravity.BOTTOM;

        root.addView(webView,        fill);
        root.addView(recycler,       fill);
        root.addView(progress,       pb);
        root.addView(bannerContainer, bcParams);
        root.addView(bottomNav,      nav);
        setContentView(root);
    }

    // ── Firestore listener ────────────────────────────────────
    @SuppressWarnings("unchecked")
    private void startListening() {
        listener = db.collection("apps")
            .document(OWNER_ID)
            .collection("list")
            .document(APP_ID)
            .addSnapshotListener((snap, err) -> {
                if (err != null || snap == null || !snap.exists()) return;

                // Primary color
                String pc = snap.getString("config.primaryColor");
                if (pc != null && !pc.isEmpty()) {
                    primaryColor = pc;
                    try { getWindow().setStatusBarColor(Color.parseColor(pc)); }
                    catch (Exception ignored) {}
                }

                // Rebuild nav tabs from config
                navTabs.clear();

                // 1. Ana menü bölümleri (config.menu[])
                List<Object> menuRaw = (List<Object>) snap.get("config.menu");
                if (menuRaw != null) {
                    for (Object o : menuRaw) {
                        if (!(o instanceof Map)) continue;
                        Map<String,Object> m = (Map<String,Object>) o;
                        if (!Boolean.FALSE.equals(m.get("active"))) {
                            Map<String,Object> tab = new HashMap<>(m);
                            tab.put("_source", "menu");
                            navTabs.add(tab);
                        }
                    }
                }

                // 2. IPTV bölümleri (config.iptv[])
                List<Object> iptvRaw = (List<Object>) snap.get("config.iptv");
                if (iptvRaw != null) {
                    for (Object o : iptvRaw) {
                        if (!(o instanceof Map)) continue;
                        Map<String,Object> m = (Map<String,Object>) o;
                        if (!Boolean.FALSE.equals(m.get("active"))) {
                            Map<String,Object> tab = new HashMap<>(m);
                            tab.put("_source", "iptv");
                            tab.put("type", "iptv");
                            navTabs.add(tab);
                        }
                    }
                }

                // 3. Video bölümleri (config.videos[])
                List<Object> videosRaw = (List<Object>) snap.get("config.videos");
                if (videosRaw != null) {
                    for (Object o : videosRaw) {
                        if (!(o instanceof Map)) continue;
                        Map<String,Object> m = (Map<String,Object>) o;
                        if (!Boolean.FALSE.equals(m.get("active"))) {
                            Map<String,Object> tab = new HashMap<>(m);
                            tab.put("_source", "video");
                            tab.put("type", "video");
                            navTabs.add(tab);
                        }
                    }
                }

                // Reklam config'ini oku
                final Map<String,Object> adsConfig = snap.contains("config.ads") ?
                    (Map<String,Object>) snap.get("config.ads") : null;

                runOnUiThread(new Runnable() {
                    @Override public void run() {
                        // Reklamları ilk seferinde init et
                        if (adsConfig != null && adManager != null && bannerContainer != null) {
                            adManager.init(adsConfig, bannerContainer);
                        }
                        buildNav();
                        if (activeTab < 0 && !navTabs.isEmpty()) {
                            openTab(0);
                        } else if (navTabs.isEmpty()) {
                            showWeb(DEFAULT_URL);
                        }
                    }
                });
            });
    }

    // ── Build bottom nav ──────────────────────────────────────
    private void buildNav() {
        bottomNav.removeAllViews();
        if (navTabs.size() <= 1) { bottomNav.setVisibility(View.GONE); return; }
        bottomNav.setVisibility(View.VISIBLE);

        int selColor;
        try { selColor = Color.parseColor(primaryColor); }
        catch (Exception e) { selColor = Color.parseColor("#6c63ff"); }

        for (int i = 0; i < navTabs.size(); i++) {
            final int idx = i;
            Map<String,Object> tab = navTabs.get(i);
            String title = str(tab, "title", "");
            String icon  = str(tab, "icon", "");
            boolean sel  = (i == activeTab);

            LinearLayout btn = new LinearLayout(this);
            btn.setOrientation(LinearLayout.VERTICAL);
            btn.setGravity(Gravity.CENTER);
            btn.setLayoutParams(new LinearLayout.LayoutParams(0, -1, 1f));
            btn.setBackgroundColor(sel ? Color.parseColor("#1a1a2e") : Color.TRANSPARENT);
            btn.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View v) { openTab(idx); }
            });

            int color = sel ? selColor : Color.parseColor("#606080");

            if (!icon.isEmpty()) {
                TextView iv = new TextView(this);
                iv.setText(icon); iv.setTextSize(18); iv.setGravity(Gravity.CENTER);
                iv.setTextColor(color);
                btn.addView(iv);
            }

            TextView tv = new TextView(this);
            tv.setText(title); tv.setTextSize(9); tv.setGravity(Gravity.CENTER);
            tv.setTextColor(color);
            btn.addView(tv);

            bottomNav.addView(btn);
        }
    }

    // ── Open tab ──────────────────────────────────────────────
    @SuppressWarnings("unchecked")
    private void openTab(int idx) {
        if (idx < 0 || idx >= navTabs.size()) return;
        activeTab = idx;
        buildNav();

        Map<String,Object> tab  = navTabs.get(idx);
        // Geçiş reklamı tetikle
        if (adManager != null) {
            String tabTitle = str(tab, "title", "");
            adManager.onTabChange(tabTitle);
        }
        String type    = str(tab, "type",    "web");
        String display = str(tab, "display", "list");
        String url     = str(tab, "url",     "");

        if ("iptv".equals(type)) {
            // Aktif kanalları filtrele
            List<Object> raw = (List<Object>) tab.get("items");
            List<Map<String,Object>> channels = new ArrayList<>();
            if (raw != null) {
                for (Object o : raw) {
                    if (!(o instanceof Map)) continue;
                    Map<String,Object> ch = (Map<String,Object>) o;
                    if (!Boolean.FALSE.equals(ch.get("active"))) channels.add(ch);
                }
            }

            if (!channels.isEmpty()) {
                if ("single".equals(display)) {
                    // Tek mod: ilk kanalı direkt aç
                    Map<String,Object> ch = channels.get(0);
                    play(str(ch,"url",""), str(ch,"name",""),
                         str(ch,"referer",""), str(ch,"origin",""));
                } else {
                    showList(channels, display);
                }
            } else if (!url.isEmpty()) {
                // M3U URL'den APK içinde parse et
                parseM3u(url, display);
            } else {
                toast("İçerik bulunamadı");
            }

        } else if ("video".equals(type)) {
            play(url, str(tab,"title",""), str(tab,"referer",""), str(tab,"origin",""));

        } else {
            // web / rss / default
            showWeb(url.isEmpty() ? DEFAULT_URL : url);
        }
    }

    // ── Show WebView ──────────────────────────────────────────
    private void showWeb(String url) {
        webView.setVisibility(View.VISIBLE);
        recycler.setVisibility(View.GONE);
        if (!url.isEmpty() && !url.equals(webView.getUrl())) {
            progress.setVisibility(View.VISIBLE);
            webView.loadUrl(url);
        }
    }

    // ── Show channel list ─────────────────────────────────────
    private void showList(final List<Map<String,Object>> items, String display) {
        webView.setVisibility(View.GONE);
        recycler.setVisibility(View.VISIBLE);

        recycler.setLayoutManager("grid".equals(display)
            ? new GridLayoutManager(this, 3)
            : new LinearLayoutManager(this));

        recycler.setAdapter(new ContentAdapter(this, items, display, primaryColor,
            new ContentAdapter.OnItemClick() {
                @Override public void onClick(Map<String,Object> item) {
                    play(str(item,"url",""), str(item,"name",""),
                         str(item,"referer",""), str(item,"origin",""));
                }
            }));
    }

    // ── Parse M3U (background) ────────────────────────────────
    private void parseM3u(final String m3uUrl, final String display) {
        progress.setVisibility(View.VISIBLE);
        webView.setVisibility(View.GONE);
        recycler.setVisibility(View.GONE);

        new Thread(new Runnable() {
            @Override public void run() {
                try {
                    List<M3uParser.Channel> ch = M3uParser.parseFromUrl(m3uUrl);
                    final List<Map<String,Object>> items = new ArrayList<>();
                    for (M3uParser.Channel c : ch) items.add(c.toMap());

                    runOnUiThread(new Runnable() {
                        @Override public void run() {
                            progress.setVisibility(View.GONE);
                            if (items.isEmpty()) { toast("Liste boş"); return; }
                            if ("single".equals(display)) {
                                Map<String,Object> item = items.get(0);
                                play(str(item,"url",""), str(item,"name",""),
                                     str(item,"referer",""), str(item,"origin",""));
                            } else {
                                showList(items, display);
                            }
                        }
                    });
                } catch (final Exception e) {
                    runOnUiThread(new Runnable() {
                        @Override public void run() {
                            progress.setVisibility(View.GONE);
                            toast("Yükleme hatası: " + e.getMessage());
                        }
                    });
                }
            }
        }).start();
    }

    // ── Open player ───────────────────────────────────────────
    void play(String url, String title, String referer, String origin) {
        if (url == null || url.trim().isEmpty()) { toast("URL bulunamadı"); return; }
        try {
            Intent i = new Intent(this, PlayerActivity.class);
            i.putExtra("url",     url.trim());
            i.putExtra("title",   title   != null ? title   : "");
            i.putExtra("referer", referer != null ? referer : "");
            i.putExtra("origin",  origin  != null ? origin  : "");
            startActivity(i);
        } catch (Exception e) {
            toast("Player hatası: " + e.getMessage());
        }
    }

    // ── Helpers ───────────────────────────────────────────────
    static String str(Map<String,Object> m, String k, String def) {
        if (m == null) return def;
        Object v = m.get(k);
        return (v instanceof String && !((String)v).isEmpty()) ? (String)v : def;
    }
    int dp(int v) { return Math.round(v * getResources().getDisplayMetrics().density); }
    void toast(String msg) { Toast.makeText(this, msg, Toast.LENGTH_SHORT).show(); }

    @Override public void onBackPressed() {
        if (webView.getVisibility() == View.VISIBLE && webView.canGoBack()) webView.goBack();
        else super.onBackPressed();
    }
    @Override protected void onDestroy() {
        super.onDestroy();
        if (listener   != null) listener.remove();
        if (adManager  != null) adManager.onDestroy();
    }
}

JAVA_MAINACTIVITY_EOF
sed -i "s/PACKAGE_PLACEHOLDER/${PACKAGE_NAME}/g" "app/src/main/java/$PKG_PATH/MainActivity.java"
sed -i "s/OWNER_ID_PLACEHOLDER/${OWNER_ID}/g"          "app/src/main/java/$PKG_PATH/MainActivity.java"
sed -i "s/APP_ID_PLACEHOLDER/${APP_ID}/g"              "app/src/main/java/$PKG_PATH/MainActivity.java"
sed -i "s/APP_TOPIC_PLACEHOLDER/app_${APP_ID}/g"       "app/src/main/java/$PKG_PATH/MainActivity.java"
sed -i "s|CONTENT_URL_PLACEHOLDER|${CONTENT_URL:-https://example.com}|g" "app/src/main/java/$PKG_PATH/MainActivity.java"
echo "MainActivity.java yazıldı"

cat > "app/src/main/java/$PKG_PATH/PlayerActivity.java" << 'JAVA_PLAYERACTIVITY_EOF'
package PACKAGE_PLACEHOLDER;

import android.app.Activity;
import android.content.pm.ActivityInfo;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.view.GestureDetector;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.TextView;
import android.widget.Toast;
import androidx.media3.common.C;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.common.util.Util;
import androidx.media3.datasource.DataSource;
import androidx.media3.datasource.DefaultDataSource;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.datasource.ResolvingDataSource;
import androidx.media3.exoplayer.DefaultLoadControl;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.dash.DashMediaSource;
import androidx.media3.exoplayer.hls.HlsMediaSource;
import androidx.media3.exoplayer.rtsp.RtspMediaSource;
import androidx.media3.exoplayer.smoothstreaming.SsMediaSource;
import androidx.media3.exoplayer.source.MediaSource;
import androidx.media3.exoplayer.source.ProgressiveMediaSource;
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector;
import androidx.media3.ui.AspectRatioFrameLayout;
import androidx.media3.ui.PlayerView;
import java.util.HashMap;
import java.util.Map;

public class PlayerActivity extends Activity {

    private static final int[] MODES = {
        AspectRatioFrameLayout.RESIZE_MODE_FILL,
        AspectRatioFrameLayout.RESIZE_MODE_FIT,
        AspectRatioFrameLayout.RESIZE_MODE_ZOOM,
        AspectRatioFrameLayout.RESIZE_MODE_FIXED_WIDTH,
        AspectRatioFrameLayout.RESIZE_MODE_FIXED_HEIGHT,
    };
    private static final String[] MLBLS = {"FILL","FIT","ZOOM","W-FIX","H-FIX"};
    private int modeIdx = 0;

    private ExoPlayer  player;
    private PlayerView playerView;
    private View       overlay;
    private TextView   timeTv, modeTv, playTv;
    private SeekBar    seekBar;
    private boolean    ctrlVisible = true;
    private boolean    locked = false;
    private float      speed  = 1f;
    private Handler    handler;

    private ScaleGestureDetector scaleGD;
    private GestureDetector      tapGD;

    private final Runnable hideRun = new Runnable() {
        @Override public void run() { if (!locked) hideCtrl(); }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(
            WindowManager.LayoutParams.FLAG_FULLSCREEN,
            WindowManager.LayoutParams.FLAG_FULLSCREEN);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
        handler = new Handler();

        String url     = getIntent().getStringExtra("url");
        String title   = getIntent().getStringExtra("title");
        String referer = getIntent().getStringExtra("referer");
        String origin  = getIntent().getStringExtra("origin");

        if (url     == null) url     = "";
        if (title   == null) title   = "";
        if (referer == null) referer = "";
        if (origin  == null) origin  = "";

        if (url.trim().isEmpty()) { finish(); return; }

        buildLayout(title);
        buildPlayer(url.trim(), referer.trim(), origin.trim());
        scheduleHide();
    }

    private void buildLayout(final String title) {
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);

        playerView = new PlayerView(this);
        playerView.setResizeMode(MODES[modeIdx]);
        playerView.setUseController(false);
        playerView.setKeepScreenOn(true);
        root.addView(playerView, new FrameLayout.LayoutParams(-1, -1));

        // Gesture layer
        View gl = new View(this);
        scaleGD = new ScaleGestureDetector(this,
            new ScaleGestureDetector.SimpleOnScaleGestureListener() {
                @Override public boolean onScale(ScaleGestureDetector d) {
                    float f  = d.getScaleFactor();
                    float sx = Math.max(0.5f, Math.min(playerView.getScaleX() * f, 5f));
                    playerView.setScaleX(sx);
                    playerView.setScaleY(sx);
                    return true;
                }
            });
        tapGD = new GestureDetector(this,
            new GestureDetector.SimpleOnGestureListener() {
                @Override public boolean onSingleTapUp(MotionEvent e) { toggleCtrl(); return true; }
                @Override public boolean onDoubleTap(MotionEvent e) {
                    // Çift tık: zoom sıfırla
                    playerView.setScaleX(1f); playerView.setScaleY(1f); return true;
                }
                @Override public boolean onFling(MotionEvent e1, MotionEvent e2, float vx, float vy) {
                    // Yatay swipe: ileri/geri 30s
                    if (Math.abs(vx) > Math.abs(vy) && player != null) {
                        long seek = vx > 0 ? 30000 : -30000;
                        player.seekTo(Math.max(0, player.getCurrentPosition() + seek));
                    }
                    return true;
                }
            });
        gl.setOnTouchListener(new View.OnTouchListener() {
            @Override public boolean onTouch(View v, MotionEvent e) {
                scaleGD.onTouchEvent(e);
                tapGD.onTouchEvent(e);
                return true;
            }
        });
        root.addView(gl, new FrameLayout.LayoutParams(-1, -1));

        overlay = buildControls(title);
        root.addView(overlay, new FrameLayout.LayoutParams(-1, -1));
        setContentView(root);

        // Seek updater
        handler.post(new Runnable() {
            @Override public void run() {
                try {
                    if (player != null && player.getDuration() > 0) {
                        long pos = player.getCurrentPosition();
                        long dur = player.getDuration();
                        if (seekBar != null) {
                            seekBar.setMax((int)(dur / 1000));
                            seekBar.setProgress((int)(pos / 1000));
                        }
                        if (timeTv != null) timeTv.setText(fmt(pos) + " / " + fmt(dur));
                    }
                } catch (Exception ignored) {}
                handler.postDelayed(this, 500);
            }
        });
    }

    private View buildControls(String title) {
        FrameLayout ov = new FrameLayout(this);

        // Top bar
        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        top.setBackgroundColor(Color.parseColor("#CC000000"));
        top.setPadding(dp(12), dp(10), dp(12), dp(10));
        FrameLayout.LayoutParams tp = new FrameLayout.LayoutParams(-1, -2);
        tp.gravity = Gravity.TOP;

        TextView back = mkTv("←", 22, Color.WHITE, dp(14), 0);
        back.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { finish(); }
        });

        TextView ttv = mkTv(title, 14, Color.WHITE, 0, 0);
        ttv.setMaxLines(1);
        ttv.setEllipsize(android.text.TextUtils.TruncateAt.END);
        ttv.setLayoutParams(new LinearLayout.LayoutParams(0, -2, 1f));

        modeTv = mkTv(MLBLS[modeIdx], 11, Color.parseColor("#aaaaff"), dp(8), dp(8));
        modeTv.setBackgroundColor(Color.parseColor("#441a1a2e"));
        modeTv.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { cycleMode(); scheduleHide(); }
        });

        top.addView(back); top.addView(ttv); top.addView(modeTv);
        ov.addView(top, tp);

        // Bottom bar
        LinearLayout bot = new LinearLayout(this);
        bot.setOrientation(LinearLayout.VERTICAL);
        bot.setBackgroundColor(Color.parseColor("#CC000000"));
        bot.setPadding(dp(12), dp(8), dp(12), dp(14));
        FrameLayout.LayoutParams bp = new FrameLayout.LayoutParams(-1, -2);
        bp.gravity = Gravity.BOTTOM;

        // Seek
        LinearLayout seekRow = new LinearLayout(this);
        seekRow.setOrientation(LinearLayout.HORIZONTAL);
        seekRow.setGravity(Gravity.CENTER_VERTICAL);

        timeTv = mkTv("--:--", 11, Color.WHITE, 0, 0);
        timeTv.setMinWidth(dp(90));

        seekBar = new SeekBar(this);
        seekBar.setProgressTintList(android.content.res.ColorStateList.valueOf(Color.parseColor("#6c63ff")));
        seekBar.setThumbTintList(android.content.res.ColorStateList.valueOf(Color.WHITE));
        seekBar.setLayoutParams(new LinearLayout.LayoutParams(0, -2, 1f));
        seekBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar s, int p, boolean u) {
                if (u && player != null) player.seekTo((long)p * 1000);
            }
            @Override public void onStartTrackingTouch(SeekBar s) { handler.removeCallbacks(hideRun); }
            @Override public void onStopTrackingTouch(SeekBar s) { scheduleHide(); }
        });
        seekRow.addView(timeTv); seekRow.addView(seekBar);

        // Buttons
        LinearLayout btnRow = new LinearLayout(this);
        btnRow.setOrientation(LinearLayout.HORIZONTAL);
        btnRow.setGravity(Gravity.CENTER);
        btnRow.setPadding(0, dp(8), 0, 0);

        // «30
        TextView rw = ctrlBtn("«30");
        rw.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                if (player != null) player.seekTo(Math.max(0, player.getCurrentPosition()-30000));
                scheduleHide();
            }
        });

        // Play/Pause
        playTv = ctrlBtn("⏸"); playTv.setTextSize(26);
        playTv.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                if (player == null) return;
                if (player.isPlaying()) { player.pause(); playTv.setText("▶"); }
                else                    { player.play();  playTv.setText("⏸"); }
                scheduleHide();
            }
        });

        // 30»
        TextView fw = ctrlBtn("30»");
        fw.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                if (player != null) player.seekTo(player.getCurrentPosition()+30000);
                scheduleHide();
            }
        });

        // Speed
        final float[]  speeds = {0.25f,0.5f,0.75f,1f,1.25f,1.5f,2f,3f};
        final String[] spLbl  = {"0.25x","0.5x","0.75x","1x","1.25x","1.5x","2x","3x"};
        final int[]    spIdx  = {3};
        final TextView spTv   = ctrlBtn("1x");
        spTv.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                spIdx[0] = (spIdx[0]+1) % speeds.length;
                speed = speeds[spIdx[0]];
                spTv.setText(spLbl[spIdx[0]]);
                if (player != null) player.setPlaybackSpeed(speed);
                scheduleHide();
            }
        });

        // Aspect/Mode
        final TextView modBtn = ctrlBtn("⊡");
        modBtn.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { cycleMode(); scheduleHide(); }
        });

        // Zoom reset
        final TextView zr = ctrlBtn("1:1");
        zr.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                playerView.setScaleX(1f); playerView.setScaleY(1f); scheduleHide();
            }
        });

        // Lock
        final TextView lk = ctrlBtn("🔓");
        lk.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                locked = !locked;
                lk.setText(locked ? "🔒" : "🔓");
                if (locked) hideCtrl();
                else showCtrl();
            }
        });

        btnRow.addView(rw); btnRow.addView(playTv); btnRow.addView(fw);
        btnRow.addView(spTv); btnRow.addView(modBtn); btnRow.addView(zr); btnRow.addView(lk);

        bot.addView(seekRow); bot.addView(btnRow);
        ov.addView(bot, bp);
        return ov;
    }

    // ── ExoPlayer builder ─────────────────────────────────────
    private void buildPlayer(String url, String referer, String origin) {
        DefaultTrackSelector ts = new DefaultTrackSelector(this);
        ts.setParameters(ts.buildUponParameters()
            .setPreferredAudioLanguage("tr")
            .setMaxVideoSizeSd()
            .build());

        // Aggressive buffering for live streams
        DefaultLoadControl lc = new DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                10_000,   // min buffer
                60_000,   // max buffer
                1_500,    // buffer for playback
                3_000)    // buffer for playback after rebuffer
            .build();

        player = new ExoPlayer.Builder(this)
            .setTrackSelector(ts)
            .setLoadControl(lc)
            .build();
        playerView.setPlayer(player);

        // DataSource with full headers
        DefaultHttpDataSource.Factory httpDsf = new DefaultHttpDataSource.Factory()
            .setUserAgent("Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36")
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(20_000)
            .setAllowCrossProtocolRedirects(true);

        // Inject Referer + Origin headers
        if (!referer.isEmpty() || !origin.isEmpty()) {
            Map<String,String> headers = new HashMap<>();
            if (!referer.isEmpty()) headers.put("Referer", referer);
            if (!origin.isEmpty())  headers.put("Origin",  origin);
            headers.put("Accept","*/*");
            headers.put("Accept-Language","tr-TR,tr;q=0.9,en;q=0.8");
            httpDsf.setDefaultRequestProperties(headers);
        }

        DataSource.Factory dsf = new DefaultDataSource.Factory(this, httpDsf);

        MediaSource ms = detectAndBuildSource(url, dsf);
        player.setMediaSource(ms, true);
        player.prepare();
        player.setPlayWhenReady(true);
        player.setPlaybackSpeed(speed);
        player.setRepeatMode(Player.REPEAT_MODE_OFF);

        player.addListener(new Player.Listener() {
            @Override public void onIsPlayingChanged(boolean playing) {
                if (playTv != null) playTv.setText(playing ? "⏸" : "▶");
            }
            @Override public void onPlaybackStateChanged(int state) {
                // Auto-retry on buffering timeout
            }
            @Override public void onPlayerError(PlaybackException e) {
                // Try progressive fallback on error
                String msg = e.getMessage() != null ? e.getMessage() : "Bilinmeyen hata";
                Toast.makeText(PlayerActivity.this, "Hata: " + msg, Toast.LENGTH_LONG).show();
            }
        });
    }

    private MediaSource detectAndBuildSource(String url, DataSource.Factory dsf) {
        Uri uri = Uri.parse(url);
        // Detect by Content-Type hint from @type param or URL extension
        String lo = url.toLowerCase();

        // DASH
        if (lo.contains(".mpd") || lo.contains("dash") || lo.contains("manifest"))
            return new DashMediaSource.Factory(dsf).createMediaSource(MediaItem.fromUri(uri));

        // HLS — m3u8 veya .m3u veya hiçbir uzantı yoksa da dene
        if (lo.contains(".m3u8") || lo.contains("m3u8") || lo.contains(".m3u"))
            return new HlsMediaSource.Factory(dsf).createMediaSource(MediaItem.fromUri(uri));

        // RTSP
        if (lo.startsWith("rtsp://") || lo.startsWith("rtsps://"))
            return new RtspMediaSource.Factory().createMediaSource(MediaItem.fromUri(uri));

        // Smooth Streaming
        if (lo.contains(".ism") || lo.contains("smooth"))
            return new SsMediaSource.Factory(dsf).createMediaSource(MediaItem.fromUri(uri));

        // Progressive (mp4, mkv, avi, ts, flv, webm, opus, aac, mp3...)
        if (lo.contains(".mp4") || lo.contains(".mkv") || lo.contains(".avi") ||
            lo.contains(".ts")  || lo.contains(".flv") || lo.contains(".webm") ||
            lo.contains(".mp3") || lo.contains(".aac") || lo.contains(".opus"))
            return new ProgressiveMediaSource.Factory(dsf).createMediaSource(MediaItem.fromUri(uri));

        // Uzantısız URL — önce HLS dene (canlı yayınlar genellikle HLS)
        if (!lo.contains(".")) {
            return new HlsMediaSource.Factory(dsf).createMediaSource(MediaItem.fromUri(uri));
        }

        // Varsayılan: Progressive
        return new ProgressiveMediaSource.Factory(dsf).createMediaSource(MediaItem.fromUri(uri));
    }

    private void cycleMode() {
        modeIdx = (modeIdx + 1) % MODES.length;
        playerView.setResizeMode(MODES[modeIdx]);
        if (modeTv != null) modeTv.setText(MLBLS[modeIdx]);
    }

    // Controls
    private void toggleCtrl() { if (locked) return; if (ctrlVisible) hideCtrl(); else showCtrl(); }
    private void showCtrl()   { ctrlVisible=true;  if(overlay!=null) overlay.animate().alpha(1f).setDuration(180).start(); scheduleHide(); }
    private void hideCtrl()   { ctrlVisible=false; if(overlay!=null) overlay.animate().alpha(0f).setDuration(280).start(); }
    private void scheduleHide(){ handler.removeCallbacks(hideRun); handler.postDelayed(hideRun,4000); }

    // Helpers
    private TextView mkTv(String txt, float sp, int color, int pr, int pl) {
        TextView tv = new TextView(this);
        tv.setText(txt); tv.setTextSize(sp); tv.setTextColor(color);
        tv.setPadding(pl, 0, pr, 0); tv.setGravity(Gravity.CENTER);
        return tv;
    }
    private TextView ctrlBtn(String lbl) {
        TextView tv = new TextView(this);
        tv.setText(lbl); tv.setTextSize(15); tv.setTextColor(Color.WHITE);
        tv.setPadding(dp(14), dp(8), dp(14), dp(8)); tv.setGravity(Gravity.CENTER);
        return tv;
    }
    private String fmt(long ms) {
        long s=ms/1000, m=s/60; s=s%60; long h=m/60; m=m%60;
        return h>0 ? String.format("%d:%02d:%02d",h,m,s) : String.format("%d:%02d",m,s);
    }
    int dp(int v){ return Math.round(v * getResources().getDisplayMetrics().density); }

    @Override protected void onStop()    { super.onStop(); if(player!=null) player.pause(); }
    @Override protected void onDestroy() {
        super.onDestroy();
        handler.removeCallbacksAndMessages(null);
        if(player!=null){ player.release(); player=null; }
    }
    @Override public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if(hasFocus) getWindow().getDecorView().setSystemUiVisibility(
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY |
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION  |
            View.SYSTEM_UI_FLAG_FULLSCREEN);
    }
}

JAVA_PLAYERACTIVITY_EOF
sed -i "s/PACKAGE_PLACEHOLDER/${PACKAGE_NAME}/g" "app/src/main/java/$PKG_PATH/PlayerActivity.java"
echo "PlayerActivity.java yazıldı"

cat > "app/src/main/java/$PKG_PATH/ContentAdapter.java" << 'JAVA_CONTENTADAPTER_EOF'
package PACKAGE_PLACEHOLDER;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public class ContentAdapter extends RecyclerView.Adapter<ContentAdapter.VH> {

    public interface OnItemClick { void onClick(Map<String,Object> item); }

    private static final int TYPE_HEADER = 0;
    private static final int TYPE_ITEM   = 1;

    private final Context     ctx;
    private final String      display;
    private final String      primaryColor;
    private final OnItemClick listener;
    private final List<Object> flat = new ArrayList<>();

    public ContentAdapter(Context ctx, List<Map<String,Object>> items,
                          String display, String primaryColor, OnItemClick listener) {
        this.ctx          = ctx;
        this.display      = display;
        this.primaryColor = primaryColor;
        this.listener     = listener;
        buildFlat(items);
    }

    @SuppressWarnings("unchecked")
    private void buildFlat(List<Map<String,Object>> items) {
        flat.clear();
        // Group by "group" field
        Map<String, List<Map<String,Object>>> groups = new LinkedHashMap<>();
        for (Map<String,Object> item : items) {
            Object g = item.get("group");
            String gStr = (g instanceof String) ? (String)g : "";
            if (!groups.containsKey(gStr)) groups.put(gStr, new ArrayList<>());
            groups.get(gStr).add(item);
        }
        for (Map.Entry<String, List<Map<String,Object>>> e : groups.entrySet()) {
            if (!e.getKey().isEmpty()) flat.add(e.getKey()); // header
            flat.addAll(e.getValue());
        }
    }

    @Override public int getItemViewType(int pos) {
        return flat.get(pos) instanceof String ? TYPE_HEADER : TYPE_ITEM;
    }

    @NonNull @Override
    public VH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        if (viewType == TYPE_HEADER) return buildHeaderVH();
        return "grid".equals(display) ? buildGridVH() : buildListVH();
    }

    @Override @SuppressWarnings("unchecked")
    public void onBindViewHolder(@NonNull VH vh, int pos) {
        Object obj = flat.get(pos);
        if (obj instanceof String) {
            if (vh.title != null) vh.title.setText((String)obj);
            return;
        }
        Map<String,Object> item = (Map<String,Object>) obj;
        String name  = s(item,"name");
        String logo  = s(item,"logo");
        String group = s(item,"group");

        if (vh.title    != null) vh.title.setText(name);
        if (vh.subtitle != null) vh.subtitle.setText(group);
        if (vh.letter   != null) vh.letter.setText(name.isEmpty() ? "?" : name.substring(0,1).toUpperCase());
        if (vh.logo     != null && !logo.isEmpty()) loadImg(logo, vh.logo);

        vh.root.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { listener.onClick(item); }
        });
    }

    @Override public int getItemCount() { return flat.size(); }

    // ── ViewHolder builders ───────────────────────────────────
    private VH buildHeaderVH() {
        TextView tv = new TextView(ctx);
        tv.setPadding(dp(16), dp(12), dp(16), dp(4));
        tv.setTextSize(11); tv.setTextColor(Color.parseColor("#9090b0"));
        tv.setAllCaps(true);
        tv.setLayoutParams(new RecyclerView.LayoutParams(-1, -2));
        return new VH(tv, null, null, tv, null);
    }

    private VH buildListVH() {
        LinearLayout row = new LinearLayout(ctx);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(12), dp(10), dp(12), dp(10));
        row.setBackgroundColor(Color.parseColor("#0d0d1a"));
        row.setLayoutParams(new RecyclerView.LayoutParams(-1, -2));

        FrameLayout lf = logoFrame(dp(50), dp(8));
        ImageView   logo   = logoImg(lf);
        TextView    letter = letterTv(lf, 18);
        lf.addView(logo); lf.addView(letter);

        LinearLayout tc = new LinearLayout(ctx);
        tc.setOrientation(LinearLayout.VERTICAL);
        tc.setPadding(dp(12), 0, 0, 0);
        tc.setLayoutParams(new LinearLayout.LayoutParams(0, -2, 1f));

        TextView title = new TextView(ctx);
        title.setTextSize(14); title.setTextColor(Color.WHITE);
        title.setMaxLines(2);
        title.setEllipsize(android.text.TextUtils.TruncateAt.END);

        TextView sub = new TextView(ctx);
        sub.setTextSize(11); sub.setTextColor(Color.parseColor("#606080"));

        tc.addView(title); tc.addView(sub);

        TextView play = new TextView(ctx);
        int pc; try { pc=Color.parseColor(primaryColor); } catch(Exception e){ pc=Color.parseColor("#6c63ff"); }
        play.setText("▶"); play.setTextSize(16); play.setTextColor(pc);
        play.setPadding(dp(8),0,0,0);

        row.addView(lf); row.addView(tc); row.addView(play);
        return new VH(row, logo, letter, title, sub);
    }

    private VH buildGridVH() {
        LinearLayout col = new LinearLayout(ctx);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setGravity(Gravity.CENTER);
        col.setPadding(dp(6), dp(8), dp(6), dp(8));
        col.setBackgroundColor(Color.parseColor("#0d0d1a"));
        col.setLayoutParams(new RecyclerView.LayoutParams(-1, -2));

        FrameLayout lf     = logoFrame(dp(68), dp(10));
        ImageView   logo   = logoImg(lf);
        logo.setPadding(dp(4),dp(4),dp(4),dp(4));
        TextView    letter = letterTv(lf, 22);
        lf.addView(logo); lf.addView(letter);

        TextView title = new TextView(ctx);
        title.setTextSize(10); title.setTextColor(Color.WHITE);
        title.setGravity(Gravity.CENTER);
        title.setMaxLines(2);
        title.setEllipsize(android.text.TextUtils.TruncateAt.END);
        title.setPadding(dp(2), dp(5), dp(2), 0);

        col.addView(lf); col.addView(title);
        return new VH(col, logo, letter, title, null);
    }

    // ── Helpers ───────────────────────────────────────────────
    private FrameLayout logoFrame(int size, int radius) {
        FrameLayout f = new FrameLayout(ctx);
        f.setLayoutParams(new LinearLayout.LayoutParams(size, size));
        GradientDrawable bg = new GradientDrawable();
        bg.setShape(GradientDrawable.RECTANGLE);
        bg.setCornerRadius(radius);
        bg.setColor(Color.parseColor("#1a1a2e"));
        bg.setStroke(dp(1), Color.parseColor("#2a2a42"));
        f.setBackground(bg);
        return f;
    }
    private ImageView logoImg(FrameLayout parent) {
        ImageView iv = new ImageView(ctx);
        iv.setLayoutParams(new FrameLayout.LayoutParams(-1,-1));
        iv.setScaleType(ImageView.ScaleType.CENTER_CROP);
        return iv;
    }
    private TextView letterTv(FrameLayout parent, int sp) {
        TextView tv = new TextView(ctx);
        tv.setLayoutParams(new FrameLayout.LayoutParams(-1,-1));
        tv.setGravity(Gravity.CENTER);
        tv.setTextSize(sp); tv.setTextColor(Color.parseColor("#6c63ff"));
        tv.setTypeface(null, android.graphics.Typeface.BOLD);
        return tv;
    }

    private void loadImg(final String urlStr, final ImageView target) {
        new Thread(new Runnable() {
            @Override public void run() {
                try {
                    HttpURLConnection c = (HttpURLConnection) new URL(urlStr).openConnection();
                    c.setConnectTimeout(5000); c.setReadTimeout(8000);
                    c.setRequestProperty("User-Agent","Mozilla/5.0");
                    InputStream is = c.getInputStream();
                    final Bitmap bmp = BitmapFactory.decodeStream(is);
                    if (bmp != null) {
                        new Handler(Looper.getMainLooper()).post(new Runnable() {
                            @Override public void run() { if(target!=null) target.setImageBitmap(bmp); }
                        });
                    }
                } catch (Exception ignored) {}
            }
        }).start();
    }

    static String s(Map<String,Object> m, String k) {
        Object v = m.get(k); return (v instanceof String) ? (String)v : "";
    }
    int dp(int v) { return Math.round(v * ctx.getResources().getDisplayMetrics().density); }

    // ── ViewHolder ────────────────────────────────────────────
    static class VH extends RecyclerView.ViewHolder {
        View      root;
        ImageView logo;
        TextView  letter, title, subtitle;
        VH(View root, ImageView logo, TextView letter, TextView title, TextView subtitle) {
            super(root);
            this.root=root; this.logo=logo; this.letter=letter;
            this.title=title; this.subtitle=subtitle;
        }
    }
}

JAVA_CONTENTADAPTER_EOF
sed -i "s/PACKAGE_PLACEHOLDER/${PACKAGE_NAME}/g" "app/src/main/java/$PKG_PATH/ContentAdapter.java"
echo "ContentAdapter.java yazıldı"

cat > "app/src/main/java/$PKG_PATH/M3uParser.java" << 'JAVA_M3UPARSER_EOF'
package PACKAGE_PLACEHOLDER;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.StringReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public class M3uParser {

    public static class Channel {
        public String name    = "";
        public String url     = "";
        public String logo    = "";
        public String group   = "";
        public String referer = "";
        public String origin  = "";

        public Map<String,Object> toMap() {
            Map<String,Object> m = new HashMap<>();
            m.put("name",    name);
            m.put("url",     url);
            m.put("logo",    logo);
            m.put("group",   group);
            m.put("referer", referer);
            m.put("origin",  origin);
            m.put("active",  true);
            return m;
        }
    }

    public static List<Channel> parseFromUrl(String m3uUrl) throws Exception {
        HttpURLConnection conn = (HttpURLConnection) new URL(m3uUrl).openConnection();
        conn.setConnectTimeout(15000);
        conn.setReadTimeout(30000);
        conn.setRequestProperty("User-Agent", "VLC/3.0 LibVLC/3.0");
        BufferedReader reader = new BufferedReader(new InputStreamReader(conn.getInputStream()));
        return parse(reader);
    }

    public static List<Channel> parseFromString(String content) throws Exception {
        return parse(new BufferedReader(new StringReader(content)));
    }

    private static List<Channel> parse(BufferedReader reader) throws Exception {
        List<Channel> list = new ArrayList<>();
        Channel cur = null;
        String line;
        while ((line = reader.readLine()) != null) {
            line = line.trim();
            if (line.isEmpty() || line.equals("#EXTM3U")) continue;

            if (line.startsWith("#EXTINF:")) {
                cur = new Channel();
                int ci = line.lastIndexOf(',');
                if (ci >= 0 && ci < line.length()-1)
                    cur.name = line.substring(ci+1).trim();
                cur.logo  = attr(line, "tvg-logo");
                cur.group = attr(line, "group-title");
                String tn = attr(line, "tvg-name");
                if (!tn.isEmpty() && cur.name.isEmpty()) cur.name = tn;

            } else if (line.startsWith("#EXTVLCOPT:")) {
                if (cur != null) {
                    String opt = line.substring("#EXTVLCOPT:".length()).trim();
                    if (opt.startsWith("http-referrer="))
                        cur.referer = opt.substring("http-referrer=".length()).trim();
                    else if (opt.startsWith("http-origin="))
                        cur.origin = opt.substring("http-origin=".length()).trim();
                }
            } else if (!line.startsWith("#")) {
                if (cur == null) cur = new Channel();
                cur.url = line;
                if (cur.name.isEmpty()) cur.name = nameFromUrl(line);
                list.add(cur);
                cur = null;
            }
        }
        reader.close();
        return list;
    }

    private static String attr(String text, String key) {
        for (String q : new String[]{"\"","'"}) {
            String k = key + "=" + q;
            int idx = text.toLowerCase().indexOf(k.toLowerCase());
            if (idx >= 0) {
                int s = idx + k.length();
                int e = text.indexOf(q, s);
                if (e >= 0) return text.substring(s, e).trim();
            }
        }
        return "";
    }

    private static String nameFromUrl(String url) {
        try {
            String path = new URL(url).getPath();
            String[] parts = path.split("/");
            if (parts.length > 0) {
                String last = parts[parts.length-1];
                int dot = last.lastIndexOf('.');
                if (dot > 0) last = last.substring(0, dot);
                return last.replace("-"," ").replace("_"," ");
            }
        } catch (Exception ignored) {}
        return "Channel";
    }

    public static Map<String, List<Channel>> group(List<Channel> channels) {
        Map<String, List<Channel>> map = new LinkedHashMap<>();
        for (Channel ch : channels) {
            String g = ch.group.isEmpty() ? "Genel" : ch.group;
            if (!map.containsKey(g)) map.put(g, new ArrayList<>());
            map.get(g).add(ch);
        }
        return map;
    }
}

JAVA_M3UPARSER_EOF
sed -i "s/PACKAGE_PLACEHOLDER/${PACKAGE_NAME}/g" "app/src/main/java/$PKG_PATH/M3uParser.java"
echo "M3uParser.java yazıldı"

cat > "app/src/main/java/$PKG_PATH/AdManager.java" << 'JAVA_ADMANAGER_EOF'
package PACKAGE_PLACEHOLDER;

import android.app.Activity;
import android.content.Context;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;

// AdMob
import com.google.android.gms.ads.AdListener;
import com.google.android.gms.ads.AdRequest;
import com.google.android.gms.ads.AdSize;
import com.google.android.gms.ads.AdView;
import com.google.android.gms.ads.FullScreenContentCallback;
import com.google.android.gms.ads.LoadAdError;
import com.google.android.gms.ads.MobileAds;
import com.google.android.gms.ads.interstitial.InterstitialAd;
import com.google.android.gms.ads.interstitial.InterstitialAdLoadCallback;
import com.google.android.gms.ads.rewarded.RewardedAd;
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback;

// Unity Ads
import com.unity3d.ads.IUnityAdsInitializationListener;
import com.unity3d.ads.IUnityAdsLoadListener;
import com.unity3d.ads.IUnityAdsShowListener;
import com.unity3d.ads.UnityAds;
import com.unity3d.ads.UnityAdsShowOptions;

// AppLovin
import com.applovin.sdk.AppLovinSdk;
import com.applovin.sdk.AppLovinSdkConfiguration;
import com.applovin.mediation.MaxAd;
import com.applovin.mediation.MaxAdListener;
import com.applovin.mediation.MaxError;
import com.applovin.mediation.ads.MaxInterstitialAd;
import com.applovin.mediation.ads.MaxRewardedAd;
import com.applovin.mediation.MaxRewardedAdListener;
import com.applovin.mediation.MaxReward;

import java.util.Map;

public class AdManager {

    private static final String TAG = "AdManager";

    // AdMob
    private AdView       admobBanner;
    private InterstitialAd admobInter;
    private RewardedAd   admobRewarded;
    private int          admobInterCount = 0;
    private int          admobInterFreq  = 0;

    // Unity
    private boolean      unityReady   = false;
    private int          unityInterCount = 0;
    private int          unityInterFreq  = 0;

    // AppLovin
    private MaxInterstitialAd aplInter;
    private MaxRewardedAd  aplRewarded;
    private int            aplInterCount = 0;
    private int            aplInterFreq  = 0;

    private final Activity activity;
    private Map<String,Object> config;
    private FrameLayout  bannerContainer;

    public AdManager(Activity activity) {
        this.activity = activity;
    }

    // ── Init ──────────────────────────────────────────────────
    @SuppressWarnings("unchecked")
    public void init(Map<String,Object> adsConfig, FrameLayout bannerContainer) {
        if (adsConfig == null) return;
        this.config = adsConfig;
        this.bannerContainer = bannerContainer;

        boolean admobOn  = Boolean.TRUE.equals(adsConfig.get("admobEnabled"));
        boolean unityOn  = Boolean.TRUE.equals(adsConfig.get("unityEnabled"));
        boolean aplOn    = Boolean.TRUE.equals(adsConfig.get("aplEnabled"));

        if (admobOn)  initAdMob(adsConfig);
        if (unityOn)  initUnity(adsConfig);
        if (aplOn)    initAppLovin(adsConfig);
    }

    // ── AdMob ─────────────────────────────────────────────────
    private void initAdMob(Map<String,Object> cfg) {
        String appId    = str(cfg, "admobApp");
        String bannerId = str(cfg, "admobBanner");
        String interId  = str(cfg, "admobInter");
        String rewId    = str(cfg, "admobReward");
        String freq     = str(cfg, "admobIntFreq");
        String banPos   = str(cfg, "admobBanPos");

        admobInterFreq = parseFreq(freq);

        try { MobileAds.initialize(activity, status -> Log.d(TAG,"AdMob init ok")); }
        catch (Exception e) { Log.e(TAG,"AdMob init err: "+e.getMessage()); return; }

        // Banner
        if (!bannerId.isEmpty() && bannerContainer != null) {
            admobBanner = new AdView(activity);
            admobBanner.setAdUnitId(bannerId);
            admobBanner.setAdSize(AdSize.BANNER);
            FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.gravity = "top".equals(banPos) ? Gravity.TOP : Gravity.BOTTOM;
            bannerContainer.addView(admobBanner, lp);
            admobBanner.loadAd(new AdRequest.Builder().build());
        }

        // Interstitial preload
        if (!interId.isEmpty()) loadAdMobInter(interId);

        // Rewarded preload
        if (!rewId.isEmpty()) {
            final String id = rewId;
            RewardedAd.load(activity, id, new AdRequest.Builder().build(),
                new RewardedAdLoadCallback() {
                    @Override public void onAdLoaded(RewardedAd ad) { admobRewarded = ad; }
                    @Override public void onAdFailedToLoad(LoadAdError e) { Log.d(TAG,"Rew load fail"); }
                });
        }
    }

    private void loadAdMobInter(final String id) {
        InterstitialAd.load(activity, id, new AdRequest.Builder().build(),
            new InterstitialAdLoadCallback() {
                @Override public void onAdLoaded(InterstitialAd ad) {
                    admobInter = ad;
                }
                @Override public void onAdFailedToLoad(LoadAdError e) {
                    admobInter = null;
                    Log.d(TAG, "Inter load fail: " + e.getMessage());
                }
            });
    }

    // ── Unity Ads ─────────────────────────────────────────────
    private void initUnity(Map<String,Object> cfg) {
        String gameId  = str(cfg, "unityGame");
        String freq    = str(cfg, "unityIntFreq");
        unityInterFreq = parseFreq(freq);
        if (gameId.isEmpty()) return;

        final String bannerId = str(cfg, "unityBanner");
        final String interId  = str(cfg, "unityInter");
        final String banPos   = str(cfg, "unityBanPos");

        UnityAds.initialize(activity, gameId, false, new IUnityAdsInitializationListener() {
            @Override public void onInitializationComplete() {
                unityReady = true;
                Log.d(TAG, "Unity init ok");
                // Load banner
                if (!bannerId.isEmpty() && bannerContainer != null) {
                    activity.runOnUiThread(new Runnable() {
                        @Override public void run() { showUnityBanner(bannerId, banPos); }
                    });
                }
                // Preload inter
                if (!interId.isEmpty()) {
                    UnityAds.load(interId, new IUnityAdsLoadListener() {
                        @Override public void onUnityAdsAdLoaded(String id) { Log.d(TAG,"Unity inter loaded"); }
                        @Override public void onUnityAdsFailedToLoad(String id, UnityAds.UnityAdsLoadError err, String msg) {}
                    });
                }
            }
            @Override public void onInitializationFailed(UnityAds.UnityAdsInitializationError err, String msg) {
                Log.e(TAG, "Unity init fail: " + msg);
            }
        });
    }

    private void showUnityBanner(String placementId, String position) {
        // Unity Banner via BannerView
        try {
            com.unity3d.ads.IUnityAdsLoadListener ll = new com.unity3d.ads.IUnityAdsLoadListener() {
                @Override public void onUnityAdsAdLoaded(String id) { Log.d(TAG,"Unity banner loaded"); }
                @Override public void onUnityAdsFailedToLoad(String id, UnityAds.UnityAdsLoadError e, String m) {}
            };
            UnityAds.load(placementId, ll);
        } catch (Exception e) { Log.e(TAG, "Unity banner: " + e.getMessage()); }
    }

    // ── AppLovin MAX ──────────────────────────────────────────
    private void initAppLovin(Map<String,Object> cfg) {
        String sdkKey   = str(cfg, "aplKey");
        String bannerId = str(cfg, "aplBanner");
        String interId  = str(cfg, "aplInter");
        String rewId    = str(cfg, "aplReward");
        String banPos   = str(cfg, "aplBanPos");
        String freq     = str(cfg, "aplIntFreq");
        aplInterFreq = parseFreq(freq);

        if (sdkKey.isEmpty()) return;

        AppLovinSdk sdk = AppLovinSdk.getInstance(sdkKey, new com.applovin.sdk.AppLovinSdkSettings(activity), activity);
        sdk.initializeSdk(new AppLovinSdk.SdkInitializationListener() {
            @Override public void onSdkInitialized(AppLovinSdkConfiguration c) {
                Log.d(TAG,"AppLovin init ok");
                activity.runOnUiThread(new Runnable() {
                    @Override public void run() {
                        // AppLovin banner (MAX SDK ayrı entegrasyon gerektirir, şimdilik atla)
                        // Interstitial
                        if (!interId.isEmpty()) {
                            aplInter = new MaxInterstitialAd(interId, activity);
                            aplInter.setListener(new MaxAdListener() {
                                @Override public void onAdLoaded(MaxAd ad) {}
                                @Override public void onAdDisplayed(MaxAd ad) {}
                                @Override public void onAdHidden(MaxAd ad) { aplInter.loadAd(); }
                                @Override public void onAdClicked(MaxAd ad) {}
                                @Override public void onAdLoadFailed(String id, MaxError e) {}
                                @Override public void onAdDisplayFailed(MaxAd ad, MaxError e) {}
                            });
                            aplInter.loadAd();
                        }
                        // Rewarded
                        if (!rewId.isEmpty()) {
                            aplRewarded = MaxRewardedAd.getInstance(rewId, activity);
                            aplRewarded.setListener(new MaxRewardedAdListener() {
                                @Override public void onAdLoaded(MaxAd ad) {}
                                @Override public void onAdDisplayed(MaxAd ad) {}
                                @Override public void onAdHidden(MaxAd ad) { aplRewarded.loadAd(); }
                                @Override public void onAdClicked(MaxAd ad) {}
                                @Override public void onAdLoadFailed(String id, MaxError e) {}
                                @Override public void onAdDisplayFailed(MaxAd ad, MaxError e) {}
                                @Override public void onUserRewarded(MaxAd ad, MaxReward r) {}
                                @Override public void onRewardedVideoStarted(MaxAd ad) {}
                                @Override public void onRewardedVideoCompleted(MaxAd ad) {}
                            });
                            aplRewarded.loadAd();
                        }
                    }
                });
            }
        });
    }

    // ── Show interstitial (tab değişiminde çağır) ─────────────
    public void onTabChange(String tabTitle) {
        if (config == null) return;
        // Excluded sections kontrolü
        try {
            Object excl = config.get("excludedSections");
            if (excl instanceof java.util.List) {
                java.util.List<?> ex = (java.util.List<?>) excl;
                if (ex.contains(tabTitle)) return;
            }
        } catch (Exception ignored) {}

        // AdMob inter
        if (admobInterFreq > 0 && admobInter != null) {
            admobInterCount++;
            if (admobInterCount % admobInterFreq == 0) {
                admobInter.show(activity);
                String interId = str(config, "admobInter");
                admobInter = null;
                if (!interId.isEmpty()) loadAdMobInter(interId);
                return;
            }
        }

        // Unity inter
        String unityInterId = str(config, "unityInter");
        if (unityInterFreq > 0 && unityReady && !unityInterId.isEmpty()) {
            unityInterCount++;
            if (unityInterCount % unityInterFreq == 0) {
                UnityAds.show(activity, unityInterId, new UnityAdsShowOptions(),
                    new IUnityAdsShowListener() {
                        @Override public void onUnityAdsShowFailure(String id, UnityAds.UnityAdsShowError e, String m) {}
                        @Override public void onUnityAdsShowStart(String id) {}
                        @Override public void onUnityAdsShowClick(String id) {}
                        @Override public void onUnityAdsShowComplete(String id, UnityAds.UnityAdsShowCompletionState s) {
                            UnityAds.load(id, new IUnityAdsLoadListener() {
                                @Override public void onUnityAdsAdLoaded(String i) {}
                                @Override public void onUnityAdsFailedToLoad(String i, UnityAds.UnityAdsLoadError er, String ms) {}
                            });
                        }
                    });
                return;
            }
        }

        // AppLovin inter
        if (aplInterFreq > 0 && aplInter != null && aplInter.isReady()) {
            aplInterCount++;
            if (aplInterCount % aplInterFreq == 0) {
                aplInter.showAd();
                return;
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────
    private int parseFreq(String s) {
        try { int v = Integer.parseInt(s); return v > 0 ? v : 0; }
        catch (Exception e) { return 0; }
    }
    private static String str(Map<String,Object> m, String k) {
        Object v = m.get(k); return (v instanceof String) ? (String)v : "";
    }
    private int dpToPx(int dp) {
        return Math.round(dp * activity.getResources().getDisplayMetrics().density);
    }

    public void onDestroy() {
        try { if (admobBanner  != null) admobBanner.destroy(); }  catch (Exception ignored) {}
        // aplBanner destroy (disabled)
    }
}

JAVA_ADMANAGER_EOF
sed -i "s/PACKAGE_PLACEHOLDER/${PACKAGE_NAME}/g" "app/src/main/java/$PKG_PATH/AdManager.java"
echo "AdManager.java yazıldı"

cat > "app/src/main/java/$PKG_PATH/AppFirebaseMessagingService.java" << 'JAVA_APPFIREBASEMESSAGINGSERVICE_EOF'
package PACKAGE_PLACEHOLDER;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.Build;
import androidx.core.app.NotificationCompat;
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.Map;

public class AppFirebaseMessagingService extends FirebaseMessagingService {

    private static final String CH_ID   = "app_ch";
    private static final String CH_NAME = "Bildirimler";

    @Override
    public void onMessageReceived(RemoteMessage msg) {
        super.onMessageReceived(msg);
        Map<String,String> data = msg.getData();

        String title    = data.containsKey("title")    ? data.get("title")    : "Bildirim";
        String body     = data.containsKey("body")     ? data.get("body")     : "";
        String imageUrl = data.containsKey("imageUrl") ? data.get("imageUrl") : "";
        String clickUrl = data.containsKey("clickUrl") ? data.get("clickUrl") : "";

        createChannel();

        Intent intent;
        if (!clickUrl.isEmpty()) {
            intent = new Intent(Intent.ACTION_VIEW, Uri.parse(clickUrl));
        } else {
            intent = new Intent(this, MainActivity.class);
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
        }

        PendingIntent pi = PendingIntent.getActivity(this, 0, intent,
            PendingIntent.FLAG_ONE_SHOT | PendingIntent.FLAG_IMMUTABLE);

        NotificationCompat.Builder b = new NotificationCompat.Builder(this, CH_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pi)
            .setStyle(new NotificationCompat.BigTextStyle().bigText(body));

        if (!imageUrl.isEmpty()) {
            Bitmap bmp = fetchBitmap(imageUrl);
            if (bmp != null) {
                b.setStyle(new NotificationCompat.BigPictureStyle()
                    .bigPicture(bmp).setSummaryText(body));
                b.setLargeIcon(bmp);
            }
        }

        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        nm.notify(1001, b.build());
    }

    private void createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel ch = new NotificationChannel(
                CH_ID, CH_NAME, NotificationManager.IMPORTANCE_HIGH);
            ((NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE))
                .createNotificationChannel(ch);
        }
    }

    private Bitmap fetchBitmap(String url) {
        try {
            HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
            c.setConnectTimeout(5000); c.setReadTimeout(5000); c.connect();
            InputStream is = c.getInputStream();
            return BitmapFactory.decodeStream(is);
        } catch (Exception e) { return null; }
    }
}

JAVA_APPFIREBASEMESSAGINGSERVICE_EOF
sed -i "s/PACKAGE_PLACEHOLDER/${PACKAGE_NAME}/g" "app/src/main/java/$PKG_PATH/AppFirebaseMessagingService.java"
echo "AppFirebaseMessagingService.java yazıldı"

# AndroidManifest
cat > app/src/main/AndroidManifest.xml << MEOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="${APP_NAME}"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:usesCleartextTraffic="true"
        android:hardwareAccelerated="true"
        android:name="androidx.multidex.MultiDexApplication"
        android:theme="@style/AppTheme">
        <activity android:name=".MainActivity" android:exported="true"
            android:launchMode="singleTop"
            android:configChanges="orientation|screenSize|keyboardHidden">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <activity android:name=".PlayerActivity" android:exported="false"
            android:screenOrientation="sensorLandscape"
            android:configChanges="orientation|screenSize|keyboardHidden"/>
        <service android:name=".AppFirebaseMessagingService" android:exported="false">
            <intent-filter>
                <action android:name="com.google.firebase.MESSAGING_EVENT"/>
            </intent-filter>
        </service>
    </application>
</manifest>
MEOF

# Resources
cat > app/src/main/res/values/colors.xml << CEOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="colorPrimary">#1a1a2e</color>
    <color name="colorPrimaryDark">#0f0f1a</color>
    <color name="colorAccent">#6c63ff</color>
</resources>
CEOF

cat > app/src/main/res/values/strings.xml << SEOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">${APP_NAME}</string>
    <string name="default_notification_channel_id">app_ch</string>
</resources>
SEOF

cat > app/src/main/res/values/styles.xml << STEOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="AppTheme" parent="android:Theme.Material.Light.NoActionBar">
        <item name="android:colorPrimary">@color/colorPrimary</item>
        <item name="android:colorPrimaryDark">@color/colorPrimaryDark</item>
        <item name="android:colorAccent">@color/colorAccent</item>
        <item name="android:windowBackground">@android:color/black</item>
    </style>
</resources>
STEOF

# Icons
sudo apt-get install -y -qq imagemagick 2>/dev/null
gen_icon() {
  SZ=$1 DPI=$2
  OUT="app/src/main/res/mipmap-$DPI/ic_launcher.png"
  if [ -f /tmp/icon_src.png ]; then
    convert /tmp/icon_src.png -resize ${SZ}x${SZ} "$OUT"
  else
    convert -size ${SZ}x${SZ} xc:"#1a1a2e" -fill "#6c63ff" -gravity center \
      -pointsize $((SZ/3)) -annotate 0 "${APP_NAME:0:1}" "$OUT"
  fi
  cp "$OUT" "app/src/main/res/mipmap-$DPI/ic_launcher_round.png"
}
[ -n "$ICON_URL" ] && wget -q "$ICON_URL" -O /tmp/icon_src.png 2>/dev/null || true
gen_icon 72 hdpi; gen_icon 48 mdpi; gen_icon 96 xhdpi
gen_icon 144 xxhdpi; gen_icon 192 xxxhdpi

# gradle.properties
cat > gradle.properties << GPEOF
android.useAndroidX=true
android.enableJetifier=false
org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=512m
android.nonTransitiveRClass=true
kotlin.stdlib.default.dependency=false
GPEOF

# settings.gradle
cat > settings.gradle << SGEOF
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven { url 'https://unityads.unity3d.com/android' }
        maven { url 'https://artifacts.applovin.com/android' }
    }
}
rootProject.name = "app"
include ':app'
SGEOF

# build.gradle (root)
cat > build.gradle << BGEOF
buildscript {
    repositories { google(); mavenCentral() }
    dependencies {
        classpath 'com.android.tools.build:gradle:7.4.2'
        classpath 'com.google.gms:google-services:4.3.15'
    }
}
BGEOF

# app/build.gradle — NO OkHttp, NO okio
PKG=$PACKAGE_NAME VC=${VERSION_CODE:-1} VN=${VERSION_NAME:-1.0}
cat > app/build.gradle << ABEOF
apply plugin: 'com.android.application'
apply plugin: 'com.google.gms.google-services'

android {
    namespace '$PKG'
    compileSdkVersion 34

    defaultConfig {
        applicationId '$PKG'
        minSdkVersion 21
        targetSdkVersion 34
        versionCode $VC
        versionName '$VN'
        multiDexEnabled true
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }

    buildTypes {
        release { minifyEnabled false }
    }

    packagingOptions {
        resources {
            excludes += ['META-INF/DEPENDENCIES','META-INF/LICENSE',
                         'META-INF/NOTICE','META-INF/*.kotlin_module',
                         'META-INF/AL2.0','META-INF/LGPL2.1']
        }
    }
}

configurations.all {
    resolutionStrategy {
        force 'org.jetbrains.kotlin:kotlin-stdlib:1.8.22'
        force 'org.jetbrains.kotlin:kotlin-stdlib-common:1.8.22'
        exclude group: 'org.jetbrains.kotlin', module: 'kotlin-stdlib-jdk7'
        exclude group: 'org.jetbrains.kotlin', module: 'kotlin-stdlib-jdk8'
    }
}

dependencies {
    // Firebase
    implementation platform('com.google.firebase:firebase-bom:32.7.4')
    implementation 'com.google.firebase:firebase-firestore'
    implementation 'com.google.firebase:firebase-messaging'

    // AndroidX
    implementation 'androidx.core:core:1.9.0'
    implementation 'androidx.recyclerview:recyclerview:1.3.0'
    implementation 'androidx.multidex:multidex:2.0.1'

    // ExoPlayer Media3
    implementation 'androidx.media3:media3-exoplayer:1.2.1'
    implementation 'androidx.media3:media3-exoplayer-hls:1.2.1'
    implementation 'androidx.media3:media3-exoplayer-dash:1.2.1'
    implementation 'androidx.media3:media3-exoplayer-rtsp:1.2.1'
    implementation 'androidx.media3:media3-exoplayer-smoothstreaming:1.2.1'
    implementation 'androidx.media3:media3-ui:1.2.1'

    // AdMob
    implementation 'com.google.android.gms:play-services-ads:23.0.0'

    // Unity Ads
    implementation 'com.unity3d.ads:unity-ads:4.9.2'

    // AppLovin MAX
    implementation 'com.applovin.mediation:applovin-sdk:12.4.2'

    implementation 'org.jetbrains.kotlin:kotlin-stdlib:1.8.22'
}
ABEOF

# Gradle wrapper
mkdir -p gradle/wrapper
cat > gradle/wrapper/gradle-wrapper.properties << GWEOF
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\\://services.gradle.org/distributions/gradle-${GV}-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
GWEOF

# Build
echo "Building..."
"$GRADLE" assembleRelease --no-daemon --no-configuration-cache 2>&1 | tail -50

APK_IN="$WS/app/build/outputs/apk/release/app-release-unsigned.apk"
APK_OUT="/tmp/${PACKAGE_NAME}_v${VC}.apk"
AAB_OUT="/tmp/${PACKAGE_NAME}_v${VC}.aab"

[ -f "$APK_IN" ] || { echo "APK not found!"; find "$WS/app/build" -name "*.apk" 2>/dev/null; exit 1; }

# Sign
keytool -genkey -v -keystore /tmp/ks.jks -alias release -keyalg RSA -keysize 2048 \
  -validity 10000 -storepass android -keypass android \
  -dname "CN=App,OU=App,O=App,L=App,S=App,C=US" -noprompt 2>/dev/null

"$BUILD_TOOLS/zipalign" -v 4 "$APK_IN" /tmp/aligned.apk
"$BUILD_TOOLS/apksigner" sign --ks /tmp/ks.jks --ks-key-alias release \
  --ks-pass pass:android --key-pass pass:android --out "$APK_OUT" /tmp/aligned.apk

# AAB
"$GRADLE" bundleRelease --no-daemon --no-configuration-cache 2>&1 | tail -10
AAB_IN="$WS/app/build/outputs/bundle/release/app-release.aab"
[ -f "$AAB_IN" ] && cp "$AAB_IN" "$AAB_OUT" || echo "AAB skipped"

echo "APK_FILE=$APK_OUT" >> $GITHUB_ENV
echo "AAB_FILE=$AAB_OUT" >> $GITHUB_ENV
echo "=== DONE: $(du -sh $APK_OUT 2>/dev/null | cut -f1) ==="
