#!/bin/bash
set -e
echo "=== BUILD: $APP_NAME / $PACKAGE_NAME ==="

ANDROID_SDK="${ANDROID_HOME:-/usr/local/lib/android/sdk}"
BUILD_TOOLS=$(ls -d "$ANDROID_SDK/build-tools/"* 2>/dev/null | sort -V | tail -1)
export PATH="$BUILD_TOOLS:$ANDROID_SDK/platform-tools:$PATH"

GV="7.6.4"
GRADLE="/opt/gradle-${GV}/bin/gradle"
if [ ! -f "$GRADLE" ]; then
  wget -q "https://services.gradle.org/distributions/gradle-${GV}-bin.zip" -O /tmp/g.zip
  sudo unzip -q /tmp/g.zip -d /opt/ && rm -f /tmp/g.zip
fi

WS="/tmp/build_${APP_ID}_$$"
rm -rf "$WS" && mkdir -p "$WS" && cd "$WS"
PKG_PATH=$(echo "$PACKAGE_NAME" | tr '.' '/')
mkdir -p app/src/main/java/$PKG_PATH
mkdir -p app/src/main/res/{values,mipmap-hdpi,mipmap-mdpi,mipmap-xhdpi,mipmap-xxhdpi,mipmap-xxxhdpi}

echo "$GOOGLE_SERVICES_JSON" > app/google-services.json
python3 -c "
import json
with open('app/google-services.json') as f: d=json.load(f)
for c in d.get('client',[]): c['client_info']['android_client_info']['package_name']='${PACKAGE_NAME}'
with open('app/google-services.json','w') as f: json.dump(d,f,indent=2)
"

# ══════════════════════════════════════════════════════
# MainActivity.java
# ══════════════════════════════════════════════════════
cat > "app/src/main/java/$PKG_PATH/MainActivity.java" << 'MAINEOF'
package PACKAGE_PLACEHOLDER;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.util.Log;
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
import com.google.firebase.firestore.DocumentSnapshot;
import com.google.firebase.firestore.EventListener;
import com.google.firebase.firestore.FirebaseFirestore;
import com.google.firebase.firestore.FirebaseFirestoreException;
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

    private FrameLayout    root;
    private FrameLayout    bannerHolder;
    private WebView        webView;
    private ProgressBar    progress;
    private RecyclerView   recycler;
    private LinearLayout   bottomNav;
    private FirebaseFirestore    db;
    private ListenerRegistration configListener;
    private AdManager      adManager;
    private String         primaryColor = "#1a1a2e";
    private final List<Map<String,Object>> tabs = new ArrayList<>();
    private int activeTab = -1;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(
            WindowManager.LayoutParams.FLAG_FULLSCREEN,
            WindowManager.LayoutParams.FLAG_FULLSCREEN);
        buildUI();
        try { FirebaseMessaging.getInstance().subscribeToTopic(FCM_TOPIC); }
        catch (Throwable ignored) {}
        db = FirebaseFirestore.getInstance();
        adManager = new AdManager(this);
        listenFirestore();
    }

    private void buildUI() {
        root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);

        webView = new WebView(this);
        WebSettings ws = webView.getSettings();
        ws.setJavaScriptEnabled(true);
        ws.setDomStorageEnabled(true);
        ws.setLoadWithOverviewMode(true);
        ws.setUseWideViewPort(true);
        ws.setBuiltInZoomControls(false);
        ws.setMediaPlaybackRequiresUserGesture(false);
        ws.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        ws.setUserAgentString("Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/112.0.0.0 Mobile Safari/537.36");
        webView.setWebViewClient(new WebViewClient() {
            @Override public void onPageFinished(WebView v, String u) {
                if (progress != null) progress.setVisibility(View.GONE);
            }
        });
        webView.loadUrl(DEFAULT_URL);

        recycler = new RecyclerView(this);
        recycler.setVisibility(View.GONE);
        recycler.setBackgroundColor(Color.parseColor("#08080f"));

        progress = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        progress.setIndeterminate(true);

        bannerHolder = new FrameLayout(this);

        bottomNav = new LinearLayout(this);
        bottomNav.setOrientation(LinearLayout.HORIZONTAL);
        bottomNav.setBackgroundColor(Color.parseColor("#0f0f1a"));
        bottomNav.setVisibility(View.GONE);

        FrameLayout.LayoutParams fill = new FrameLayout.LayoutParams(-1, -1);
        FrameLayout.LayoutParams pb   = new FrameLayout.LayoutParams(-1, dp(4));
        FrameLayout.LayoutParams nav  = new FrameLayout.LayoutParams(-1, dp(56));
        nav.gravity = Gravity.BOTTOM;
        FrameLayout.LayoutParams bh   = new FrameLayout.LayoutParams(-1, -2);
        bh.gravity = Gravity.BOTTOM;
        // banner is above nav
        int navH = dp(56);
        bh.setMargins(0, 0, 0, navH);

        root.addView(webView,       fill);
        root.addView(recycler,      fill);
        root.addView(progress,      pb);
        root.addView(bannerHolder,  bh);
        root.addView(bottomNav,     nav);
        setContentView(root);
    }

    @SuppressWarnings("unchecked")
    private void listenFirestore() {
        configListener = db.collection("apps")
            .document(OWNER_ID)
            .collection("list")
            .document(APP_ID)
            .addSnapshotListener(new EventListener<DocumentSnapshot>() {
                @Override
                public void onEvent(DocumentSnapshot snap, FirebaseFirestoreException err) {
                    if (err != null) { Log.e("Main", "Firestore error: " + err); return; }
                    if (snap == null || !snap.exists()) return;
                    try { applyConfig(snap); }
                    catch (Throwable t) { Log.e("Main", "applyConfig error: " + t); }
                }
            });
    }

    @SuppressWarnings("unchecked")
    private void applyConfig(DocumentSnapshot snap) {
        // Colors
        String pc = snap.getString("config.primaryColor");
        if (pc != null && !pc.isEmpty()) {
            primaryColor = pc;
            try { getWindow().setStatusBarColor(Color.parseColor(pc)); }
            catch (Throwable ignored) {}
        }

        // Build tabs
        tabs.clear();

        // menu
        Object menuObj = snap.get("config.menu");
        if (menuObj instanceof List) {
            for (Object o : (List<?>) menuObj) {
                if (!(o instanceof Map)) continue;
                Map<String,Object> m = (Map<String,Object>) o;
                if (!Boolean.FALSE.equals(m.get("active"))) {
                    Map<String,Object> t = new HashMap<>(m);
                    if (!t.containsKey("type")) t.put("type", "web");
                    tabs.add(t);
                }
            }
        }

        // iptv
        Object iptvObj = snap.get("config.iptv");
        if (iptvObj instanceof List) {
            for (Object o : (List<?>) iptvObj) {
                if (!(o instanceof Map)) continue;
                Map<String,Object> m = (Map<String,Object>) o;
                if (!Boolean.FALSE.equals(m.get("active"))) {
                    Map<String,Object> t = new HashMap<>(m);
                    t.put("type", "iptv");
                    tabs.add(t);
                }
            }
        }

        // videos
        Object vidObj = snap.get("config.videos");
        if (vidObj instanceof List) {
            for (Object o : (List<?>) vidObj) {
                if (!(o instanceof Map)) continue;
                Map<String,Object> m = (Map<String,Object>) o;
                if (!Boolean.FALSE.equals(m.get("active"))) {
                    Map<String,Object> t = new HashMap<>(m);
                    t.put("type", "video");
                    tabs.add(t);
                }
            }
        }

        // ads
        final Map<String,Object> adsCfg;
        Object adsObj = snap.get("config.ads");
        if (adsObj instanceof Map) {
            adsCfg = (Map<String,Object>) adsObj;
        } else {
            adsCfg = null;
        }

        runOnUiThread(new Runnable() {
            @Override public void run() {
                try {
                    if (adsCfg != null && adManager != null) {
                        adManager.init(adsCfg, bannerHolder);
                    }
                } catch (Throwable t) { Log.e("Main", "Ad init: " + t); }

                buildNav();

                if (activeTab < 0 && !tabs.isEmpty()) {
                    selectTab(0);
                } else if (tabs.isEmpty()) {
                    showWeb(DEFAULT_URL);
                }
            }
        });
    }

    private void buildNav() {
        bottomNav.removeAllViews();
        if (tabs.size() <= 1) { bottomNav.setVisibility(View.GONE); return; }
        bottomNav.setVisibility(View.VISIBLE);

        int selClr;
        try { selClr = Color.parseColor(primaryColor); }
        catch (Throwable e) { selClr = 0xFF6C63FF; }

        for (int i = 0; i < tabs.size(); i++) {
            final int idx = i;
            Map<String,Object> tab = tabs.get(i);
            String title = s(tab, "title");
            String icon  = s(tab, "icon");
            boolean sel  = (i == activeTab);
            int clr = sel ? selClr : 0xFF606080;

            LinearLayout btn = new LinearLayout(this);
            btn.setOrientation(LinearLayout.VERTICAL);
            btn.setGravity(Gravity.CENTER);
            btn.setLayoutParams(new LinearLayout.LayoutParams(0, -1, 1f));
            btn.setBackgroundColor(sel ? 0xFF1a1a2e : Color.TRANSPARENT);
            btn.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View v) { selectTab(idx); }
            });

            if (!icon.isEmpty()) {
                TextView iv = new TextView(this);
                iv.setText(icon); iv.setTextSize(18);
                iv.setGravity(Gravity.CENTER); iv.setTextColor(clr);
                btn.addView(iv);
            }

            TextView tv = new TextView(this);
            tv.setText(title); tv.setTextSize(9);
            tv.setGravity(Gravity.CENTER); tv.setTextColor(clr);
            btn.addView(tv);
            bottomNav.addView(btn);
        }
    }

    @SuppressWarnings("unchecked")
    private void selectTab(int idx) {
        if (idx < 0 || idx >= tabs.size()) return;
        activeTab = idx;
        buildNav();

        Map<String,Object> tab = tabs.get(idx);
        String type    = s(tab, "type");
        String display = s(tab, "display");
        String url     = s(tab, "url");
        if (display.isEmpty()) display = "list";

        // Ad interstitial
        try { if (adManager != null) adManager.onTabChange(s(tab,"title")); }
        catch (Throwable t) { Log.e("Main", "Ad tab: " + t); }

        if ("iptv".equals(type)) {
            List<Map<String,Object>> channels = new ArrayList<>();
            Object raw = tab.get("items");
            if (raw instanceof List) {
                for (Object o : (List<?>) raw) {
                    if (!(o instanceof Map)) continue;
                    Map<String,Object> ch = (Map<String,Object>) o;
                    if (!Boolean.FALSE.equals(ch.get("active"))) channels.add(ch);
                }
            }
            if (!channels.isEmpty()) {
                if ("single".equals(display)) {
                    Map<String,Object> ch = channels.get(0);
                    openPlayer(s(ch,"url"), s(ch,"name"), s(ch,"referer"), s(ch,"origin"));
                } else {
                    showList(channels, display);
                }
            } else if (!url.isEmpty()) {
                loadM3u(url, display);
            } else {
                Toast.makeText(this, "İçerik bulunamadı", Toast.LENGTH_SHORT).show();
            }

        } else if ("video".equals(type)) {
            openPlayer(url, s(tab,"title"), s(tab,"referer"), s(tab,"origin"));

        } else {
            showWeb(url.isEmpty() ? DEFAULT_URL : url);
        }
    }

    private void showWeb(String url) {
        webView.setVisibility(View.VISIBLE);
        recycler.setVisibility(View.GONE);
        if (!url.isEmpty() && !url.equals(webView.getUrl())) {
            progress.setVisibility(View.VISIBLE);
            webView.loadUrl(url);
        }
    }

    private void showList(final List<Map<String,Object>> items, String display) {
        webView.setVisibility(View.GONE);
        recycler.setVisibility(View.VISIBLE);
        recycler.setLayoutManager("grid".equals(display)
            ? new GridLayoutManager(this, 3)
            : new LinearLayoutManager(this));
        recycler.setAdapter(new ContentAdapter(this, items, display, primaryColor,
            new ContentAdapter.OnItemClick() {
                @Override public void onClick(Map<String,Object> item) {
                    openPlayer(s(item,"url"), s(item,"name"), s(item,"referer"), s(item,"origin"));
                }
            }));
    }

    private void loadM3u(final String m3uUrl, final String display) {
        progress.setVisibility(View.VISIBLE);
        webView.setVisibility(View.GONE);
        recycler.setVisibility(View.GONE);
        new Thread(new Runnable() {
            @Override public void run() {
                try {
                    final List<M3uParser.Channel> ch = M3uParser.parseFromUrl(m3uUrl);
                    runOnUiThread(new Runnable() {
                        @Override public void run() {
                            progress.setVisibility(View.GONE);
                            if (ch.isEmpty()) {
                                Toast.makeText(MainActivity.this, "Liste boş", Toast.LENGTH_SHORT).show();
                                return;
                            }
                            List<Map<String,Object>> items = new ArrayList<>();
                            for (M3uParser.Channel c : ch) items.add(c.toMap());
                            if ("single".equals(display)) {
                                Map<String,Object> item = items.get(0);
                                openPlayer(s(item,"url"), s(item,"name"), s(item,"referer"), s(item,"origin"));
                            } else {
                                showList(items, display);
                            }
                        }
                    });
                } catch (final Exception e) {
                    runOnUiThread(new Runnable() {
                        @Override public void run() {
                            progress.setVisibility(View.GONE);
                            Toast.makeText(MainActivity.this, "Hata: " + e.getMessage(), Toast.LENGTH_LONG).show();
                        }
                    });
                }
            }
        }).start();
    }

    void openPlayer(String url, String title, String referer, String origin) {
        if (url == null || url.trim().isEmpty()) {
            Toast.makeText(this, "URL bulunamadı", Toast.LENGTH_SHORT).show();
            return;
        }
        try {
            Intent i = new Intent(this, PlayerActivity.class);
            i.putExtra("url",     url.trim());
            i.putExtra("title",   title   != null ? title   : "");
            i.putExtra("referer", referer != null ? referer : "");
            i.putExtra("origin",  origin  != null ? origin  : "");
            startActivity(i);
        } catch (Throwable t) {
            Toast.makeText(this, "Player açılamadı: " + t.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }

    static String s(Map<String,Object> m, String k) {
        if (m == null) return "";
        Object v = m.get(k);
        return (v instanceof String) ? (String) v : "";
    }
    int dp(int v) { return Math.round(v * getResources().getDisplayMetrics().density); }

    @Override public void onBackPressed() {
        if (webView.getVisibility() == View.VISIBLE && webView.canGoBack()) webView.goBack();
        else super.onBackPressed();
    }
    @Override protected void onDestroy() {
        super.onDestroy();
        try { if (configListener != null) configListener.remove(); } catch (Throwable ignored) {}
        try { if (adManager != null) adManager.destroy(); } catch (Throwable ignored) {}
    }
}
MAINEOF
sed -i "s/PACKAGE_PLACEHOLDER/${PACKAGE_NAME}/g" "app/src/main/java/$PKG_PATH/MainActivity.java"
sed -i "s/OWNER_ID_PLACEHOLDER/${OWNER_ID}/g"    "app/src/main/java/$PKG_PATH/MainActivity.java"
sed -i "s/APP_ID_PLACEHOLDER/${APP_ID}/g"         "app/src/main/java/$PKG_PATH/MainActivity.java"
sed -i "s/APP_TOPIC_PLACEHOLDER/app_${APP_ID}/g"  "app/src/main/java/$PKG_PATH/MainActivity.java"
sed -i "s|CONTENT_URL_PLACEHOLDER|${CONTENT_URL:-https://example.com}|g" "app/src/main/java/$PKG_PATH/MainActivity.java"
echo "MainActivity.java OK"

# ══════════════════════════════════════════════════════
# PlayerActivity.java
# ══════════════════════════════════════════════════════
cat > "app/src/main/java/$PKG_PATH/PlayerActivity.java" << 'PLAYEREOF'
package PACKAGE_PLACEHOLDER;

import android.app.Activity;
import android.content.pm.ActivityInfo;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.util.Log;
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
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.datasource.DataSource;
import androidx.media3.datasource.DefaultDataSource;
import androidx.media3.datasource.DefaultHttpDataSource;
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

    private static final int[]    MODES = {
        AspectRatioFrameLayout.RESIZE_MODE_FILL,
        AspectRatioFrameLayout.RESIZE_MODE_FIT,
        AspectRatioFrameLayout.RESIZE_MODE_ZOOM,
        AspectRatioFrameLayout.RESIZE_MODE_FIXED_WIDTH,
        AspectRatioFrameLayout.RESIZE_MODE_FIXED_HEIGHT
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
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,
            WindowManager.LayoutParams.FLAG_FULLSCREEN);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
        handler = new Handler();

        String url     = getIntent().getStringExtra("url");
        String title   = getIntent().getStringExtra("title");
        String referer = getIntent().getStringExtra("referer");
        String origin  = getIntent().getStringExtra("origin");
        if (url == null) url = "";
        if (title == null) title = "";
        if (referer == null) referer = "";
        if (origin == null) origin = "";

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

        View gl = new View(this);
        scaleGD = new ScaleGestureDetector(this,
            new ScaleGestureDetector.SimpleOnScaleGestureListener() {
                @Override public boolean onScale(ScaleGestureDetector d) {
                    float f = d.getScaleFactor();
                    float sx = Math.max(0.5f, Math.min(playerView.getScaleX() * f, 5f));
                    playerView.setScaleX(sx); playerView.setScaleY(sx);
                    return true;
                }
            });
        tapGD = new GestureDetector(this,
            new GestureDetector.SimpleOnGestureListener() {
                @Override public boolean onSingleTapUp(MotionEvent e) { toggleCtrl(); return true; }
                @Override public boolean onDoubleTap(MotionEvent e) {
                    playerView.setScaleX(1f); playerView.setScaleY(1f); return true;
                }
                @Override public boolean onFling(MotionEvent e1, MotionEvent e2, float vx, float vy) {
                    if (Math.abs(vx) > Math.abs(vy) && player != null) {
                        long seek = vx > 0 ? 30000 : -30000;
                        player.seekTo(Math.max(0, player.getCurrentPosition() + seek));
                    }
                    return true;
                }
            });
        gl.setOnTouchListener(new View.OnTouchListener() {
            @Override public boolean onTouch(View v, MotionEvent e) {
                scaleGD.onTouchEvent(e); tapGD.onTouchEvent(e); return true;
            }
        });
        root.addView(gl, new FrameLayout.LayoutParams(-1, -1));
        overlay = buildControls(title);
        root.addView(overlay, new FrameLayout.LayoutParams(-1, -1));
        setContentView(root);

        handler.post(new Runnable() {
            @Override public void run() {
                try {
                    if (player != null && player.getDuration() > 0) {
                        long pos = player.getCurrentPosition(), dur = player.getDuration();
                        if (seekBar != null) { seekBar.setMax((int)(dur/1000)); seekBar.setProgress((int)(pos/1000)); }
                        if (timeTv != null) timeTv.setText(fmt(pos) + " / " + fmt(dur));
                    }
                } catch (Throwable ignored) {}
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
        top.setBackgroundColor(0xCC000000);
        top.setPadding(dp(12), dp(10), dp(12), dp(10));
        FrameLayout.LayoutParams tp = new FrameLayout.LayoutParams(-1, -2);
        tp.gravity = Gravity.TOP;

        TextView back = tv("←", 22, Color.WHITE);
        back.setPadding(0, 0, dp(14), 0);
        back.setOnClickListener(new View.OnClickListener() { @Override public void onClick(View v) { finish(); } });

        TextView ttv = tv(title, 14, Color.WHITE);
        ttv.setMaxLines(1);
        ttv.setEllipsize(android.text.TextUtils.TruncateAt.END);
        ttv.setLayoutParams(new LinearLayout.LayoutParams(0, -2, 1f));

        modeTv = tv(MLBLS[modeIdx], 11, 0xFFAAAAFF);
        modeTv.setPadding(dp(8), dp(4), dp(8), dp(4));
        modeTv.setBackgroundColor(0x441a1a2e);
        modeTv.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { cycleMode(); scheduleHide(); }
        });

        top.addView(back); top.addView(ttv); top.addView(modeTv);
        ov.addView(top, tp);

        // Bottom bar
        LinearLayout bot = new LinearLayout(this);
        bot.setOrientation(LinearLayout.VERTICAL);
        bot.setBackgroundColor(0xCC000000);
        bot.setPadding(dp(12), dp(8), dp(12), dp(14));
        FrameLayout.LayoutParams bp = new FrameLayout.LayoutParams(-1, -2);
        bp.gravity = Gravity.BOTTOM;

        LinearLayout seekRow = new LinearLayout(this);
        seekRow.setOrientation(LinearLayout.HORIZONTAL);
        seekRow.setGravity(Gravity.CENTER_VERTICAL);

        timeTv = tv("--:--", 11, Color.WHITE);
        timeTv.setMinWidth(dp(90));

        seekBar = new SeekBar(this);
        seekBar.setProgressTintList(android.content.res.ColorStateList.valueOf(0xFF6C63FF));
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

        LinearLayout btnRow = new LinearLayout(this);
        btnRow.setOrientation(LinearLayout.HORIZONTAL);
        btnRow.setGravity(Gravity.CENTER);
        btnRow.setPadding(0, dp(8), 0, 0);

        // «30
        TextView rw = btn("«30");
        rw.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                if (player != null) player.seekTo(Math.max(0, player.getCurrentPosition()-30000));
                scheduleHide();
            }
        });

        // play/pause
        playTv = btn("⏸"); playTv.setTextSize(26);
        playTv.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                if (player == null) return;
                if (player.isPlaying()) { player.pause(); playTv.setText("▶"); }
                else { player.play(); playTv.setText("⏸"); }
                scheduleHide();
            }
        });

        // 30»
        TextView fw = btn("30»");
        fw.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                if (player != null) player.seekTo(player.getCurrentPosition()+30000);
                scheduleHide();
            }
        });

        // speed
        final float[]  spd  = {0.25f,0.5f,0.75f,1f,1.25f,1.5f,2f,3f};
        final String[] spL  = {"0.25x","0.5x","0.75x","1x","1.25x","1.5x","2x","3x"};
        final int[]    spI  = {3};
        final TextView spTv = btn("1x");
        spTv.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                spI[0] = (spI[0]+1) % spd.length;
                speed = spd[spI[0]]; spTv.setText(spL[spI[0]]);
                if (player != null) player.setPlaybackSpeed(speed);
                scheduleHide();
            }
        });

        // mode
        TextView modeBtn = btn("⊡");
        modeBtn.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { cycleMode(); scheduleHide(); }
        });

        // zoom reset
        TextView zr = btn("1:1");
        zr.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                playerView.setScaleX(1f); playerView.setScaleY(1f); scheduleHide();
            }
        });

        // lock
        final TextView lk = btn("🔓");
        lk.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                locked = !locked;
                lk.setText(locked ? "🔒" : "🔓");
                if (locked) hideCtrl(); else showCtrl();
            }
        });

        btnRow.addView(rw); btnRow.addView(playTv); btnRow.addView(fw);
        btnRow.addView(spTv); btnRow.addView(modeBtn); btnRow.addView(zr); btnRow.addView(lk);
        bot.addView(seekRow); bot.addView(btnRow);
        ov.addView(bot, bp);
        return ov;
    }

    private void buildPlayer(String url, String referer, String origin) {
        try {
            DefaultTrackSelector ts = new DefaultTrackSelector(this);
            ts.setParameters(ts.buildUponParameters().setPreferredAudioLanguage("tr").build());

            DefaultLoadControl lc = new DefaultLoadControl.Builder()
                .setBufferDurationsMs(15000, 60000, 2000, 5000).build();

            player = new ExoPlayer.Builder(this).setTrackSelector(ts).setLoadControl(lc).build();
            playerView.setPlayer(player);

            DefaultHttpDataSource.Factory http = new DefaultHttpDataSource.Factory()
                .setUserAgent("Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/112.0.0.0 Mobile Safari/537.36")
                .setConnectTimeoutMs(15000).setReadTimeoutMs(20000)
                .setAllowCrossProtocolRedirects(true);

            if (!referer.isEmpty() || !origin.isEmpty()) {
                Map<String,String> hdrs = new HashMap<>();
                if (!referer.isEmpty()) hdrs.put("Referer", referer);
                if (!origin.isEmpty())  hdrs.put("Origin", origin);
                hdrs.put("Accept", "*/*");
                http.setDefaultRequestProperties(hdrs);
            }

            DataSource.Factory dsf = new DefaultDataSource.Factory(this, http);
            player.setMediaSource(buildSource(url, dsf), true);
            player.prepare();
            player.setPlayWhenReady(true);
            player.setPlaybackSpeed(speed);
            player.addListener(new Player.Listener() {
                @Override public void onIsPlayingChanged(boolean p) {
                    if (playTv != null) playTv.setText(p ? "⏸" : "▶");
                }
                @Override public void onPlayerError(PlaybackException e) {
                    Toast.makeText(PlayerActivity.this, "Hata: " + e.getMessage(), Toast.LENGTH_LONG).show();
                }
            });
        } catch (Throwable t) {
            Log.e("Player", "buildPlayer error: " + t);
            Toast.makeText(this, "Player başlatılamadı: " + t.getMessage(), Toast.LENGTH_LONG).show();
            finish();
        }
    }

    private MediaSource buildSource(String url, DataSource.Factory dsf) {
        Uri    uri = Uri.parse(url);
        String lo  = url.toLowerCase();
        if (lo.contains(".mpd")  || lo.contains("dash"))   return new DashMediaSource.Factory(dsf).createMediaSource(MediaItem.fromUri(uri));
        if (lo.contains(".m3u8") || lo.contains("m3u8"))   return new HlsMediaSource.Factory(dsf).createMediaSource(MediaItem.fromUri(uri));
        if (lo.startsWith("rtsp://"))                       return new RtspMediaSource.Factory().createMediaSource(MediaItem.fromUri(uri));
        if (lo.contains(".ism"))                            return new SsMediaSource.Factory(dsf).createMediaSource(MediaItem.fromUri(uri));
        if (lo.endsWith(".m3u"))                            return new HlsMediaSource.Factory(dsf).createMediaSource(MediaItem.fromUri(uri));
        if (lo.contains(".mp4") || lo.contains(".mkv") || lo.contains(".avi") ||
            lo.contains(".ts")  || lo.contains(".flv") || lo.contains(".webm") ||
            lo.contains(".mp3") || lo.contains(".aac"))
            return new ProgressiveMediaSource.Factory(dsf).createMediaSource(MediaItem.fromUri(uri));
        // Uzantısız → HLS dene (canlı yayın)
        return new HlsMediaSource.Factory(dsf).createMediaSource(MediaItem.fromUri(uri));
    }

    private void cycleMode() {
        modeIdx = (modeIdx+1) % MODES.length;
        playerView.setResizeMode(MODES[modeIdx]);
        if (modeTv != null) modeTv.setText(MLBLS[modeIdx]);
    }
    private void toggleCtrl() { if (locked) return; if (ctrlVisible) hideCtrl(); else showCtrl(); }
    private void showCtrl()   { ctrlVisible=true;  if(overlay!=null) overlay.animate().alpha(1f).setDuration(180).start(); scheduleHide(); }
    private void hideCtrl()   { ctrlVisible=false; if(overlay!=null) overlay.animate().alpha(0f).setDuration(280).start(); }
    private void scheduleHide(){ handler.removeCallbacks(hideRun); handler.postDelayed(hideRun,4000); }

    private TextView tv(String t, float sp, int clr) {
        TextView v = new TextView(this); v.setText(t); v.setTextSize(sp);
        v.setTextColor(clr); v.setGravity(Gravity.CENTER); return v;
    }
    private TextView btn(String t) {
        TextView v = new TextView(this); v.setText(t); v.setTextSize(15);
        v.setTextColor(Color.WHITE); v.setPadding(dp(14),dp(8),dp(14),dp(8)); v.setGravity(Gravity.CENTER); return v;
    }
    private String fmt(long ms) {
        long s=ms/1000, m=s/60; s=s%60; long h=m/60; m=m%60;
        return h>0 ? String.format("%d:%02d:%02d",h,m,s) : String.format("%d:%02d",m,s);
    }
    int dp(int v) { return Math.round(v * getResources().getDisplayMetrics().density); }

    @Override protected void onStop()    { super.onStop(); try { if(player!=null) player.pause(); } catch(Throwable ignored){} }
    @Override protected void onDestroy() {
        super.onDestroy();
        handler.removeCallbacksAndMessages(null);
        try { if(player!=null){ player.release(); player=null; } } catch(Throwable ignored){}
    }
    @Override public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) getWindow().getDecorView().setSystemUiVisibility(
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_FULLSCREEN);
    }
}
PLAYEREOF
sed -i "s/PACKAGE_PLACEHOLDER/${PACKAGE_NAME}/g" "app/src/main/java/$PKG_PATH/PlayerActivity.java"
echo "PlayerActivity.java OK"

# ══════════════════════════════════════════════════════
# ContentAdapter.java
# ══════════════════════════════════════════════════════
cat > "app/src/main/java/$PKG_PATH/ContentAdapter.java" << 'CONTENTEOF'
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

    private static final int TYPE_HDR  = 0;
    private static final int TYPE_ITEM = 1;

    private final Context     ctx;
    private final String      display;
    private final String      primaryColor;
    private final OnItemClick listener;
    private final List<Object> flat = new ArrayList<>();

    @SuppressWarnings("unchecked")
    public ContentAdapter(Context ctx, List<Map<String,Object>> items,
                          String display, String primaryColor, OnItemClick listener) {
        this.ctx=ctx; this.display=display; this.primaryColor=primaryColor; this.listener=listener;
        // Group
        LinkedHashMap<String, List<Map<String,Object>>> groups = new LinkedHashMap<>();
        for (Map<String,Object> item : items) {
            Object g = item.get("group");
            String gs = (g instanceof String) ? (String)g : "";
            if (!groups.containsKey(gs)) groups.put(gs, new ArrayList<>());
            groups.get(gs).add(item);
        }
        for (Map.Entry<String, List<Map<String,Object>>> e : groups.entrySet()) {
            if (!e.getKey().isEmpty()) flat.add(e.getKey());
            flat.addAll(e.getValue());
        }
    }

    @Override public int getItemViewType(int pos) { return flat.get(pos) instanceof String ? TYPE_HDR : TYPE_ITEM; }
    @Override public int getItemCount() { return flat.size(); }

    @NonNull @Override
    public VH onCreateViewHolder(@NonNull ViewGroup parent, int vt) {
        if (vt == TYPE_HDR) {
            TextView tv = new TextView(ctx);
            tv.setPadding(dp(16),dp(12),dp(16),dp(4));
            tv.setTextSize(11); tv.setTextColor(0xFF9090B0); tv.setAllCaps(true);
            tv.setLayoutParams(new RecyclerView.LayoutParams(-1,-2));
            return new VH(tv, null, null, tv, null);
        }
        return "grid".equals(display) ? makeGridVH() : makeListVH();
    }

    @Override @SuppressWarnings("unchecked")
    public void onBindViewHolder(@NonNull VH h, int pos) {
        Object obj = flat.get(pos);
        if (obj instanceof String) { if(h.title!=null) h.title.setText((String)obj); return; }
        final Map<String,Object> item = (Map<String,Object>) obj;
        String name  = s(item,"name");
        String logo  = s(item,"logo");
        String group = s(item,"group");
        if (h.title    != null) h.title.setText(name);
        if (h.subtitle != null) h.subtitle.setText(group);
        if (h.letter   != null) h.letter.setText(name.isEmpty() ? "?" : name.substring(0,1).toUpperCase());
        if (h.logo     != null && !logo.isEmpty()) loadImg(logo, h.logo);
        h.root.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { listener.onClick(item); }
        });
    }

    private VH makeListVH() {
        LinearLayout row = new LinearLayout(ctx);
        row.setOrientation(LinearLayout.HORIZONTAL); row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(12),dp(10),dp(12),dp(10)); row.setBackgroundColor(0xFF0D0D1A);
        row.setLayoutParams(new RecyclerView.LayoutParams(-1,-2));

        FrameLayout lf = logoFr(dp(52),dp(8));
        ImageView logo = logoImg(); TextView letter = letterTv(18);
        lf.addView(logo); lf.addView(letter);

        LinearLayout tc = new LinearLayout(ctx);
        tc.setOrientation(LinearLayout.VERTICAL); tc.setPadding(dp(12),0,0,0);
        tc.setLayoutParams(new LinearLayout.LayoutParams(0,-2,1f));

        TextView title = new TextView(ctx);
        title.setTextSize(14); title.setTextColor(Color.WHITE); title.setMaxLines(2);
        title.setEllipsize(android.text.TextUtils.TruncateAt.END);

        TextView sub = new TextView(ctx);
        sub.setTextSize(11); sub.setTextColor(0xFF606080);
        tc.addView(title); tc.addView(sub);

        int pc; try{pc=Color.parseColor(primaryColor);}catch(Exception e){pc=0xFF6C63FF;}
        TextView play = new TextView(ctx);
        play.setText("▶"); play.setTextSize(16); play.setTextColor(pc); play.setPadding(dp(8),0,0,0);

        row.addView(lf); row.addView(tc); row.addView(play);
        return new VH(row, logo, letter, title, sub);
    }

    private VH makeGridVH() {
        LinearLayout col = new LinearLayout(ctx);
        col.setOrientation(LinearLayout.VERTICAL); col.setGravity(Gravity.CENTER);
        col.setPadding(dp(6),dp(8),dp(6),dp(8)); col.setBackgroundColor(0xFF0D0D1A);
        col.setLayoutParams(new RecyclerView.LayoutParams(-1,-2));

        FrameLayout lf = logoFr(dp(70),dp(12));
        ImageView logo = logoImg(); logo.setPadding(dp(4),dp(4),dp(4),dp(4));
        TextView letter = letterTv(22);
        lf.addView(logo); lf.addView(letter);

        TextView title = new TextView(ctx);
        title.setTextSize(10); title.setTextColor(Color.WHITE); title.setGravity(Gravity.CENTER);
        title.setMaxLines(2); title.setEllipsize(android.text.TextUtils.TruncateAt.END);
        title.setPadding(dp(2),dp(5),dp(2),0);

        col.addView(lf); col.addView(title);
        return new VH(col, logo, letter, title, null);
    }

    private FrameLayout logoFr(int size, int r) {
        FrameLayout f = new FrameLayout(ctx);
        f.setLayoutParams(new LinearLayout.LayoutParams(size,size));
        GradientDrawable d = new GradientDrawable();
        d.setShape(GradientDrawable.RECTANGLE); d.setCornerRadius(r);
        d.setColor(0xFF1A1A2E); d.setStroke(dp(1),0xFF2A2A42);
        f.setBackground(d); return f;
    }
    private ImageView logoImg() {
        ImageView iv = new ImageView(ctx);
        iv.setLayoutParams(new FrameLayout.LayoutParams(-1,-1));
        iv.setScaleType(ImageView.ScaleType.CENTER_CROP); return iv;
    }
    private TextView letterTv(int sp) {
        TextView tv = new TextView(ctx);
        tv.setLayoutParams(new FrameLayout.LayoutParams(-1,-1));
        tv.setGravity(Gravity.CENTER); tv.setTextSize(sp); tv.setTextColor(0xFF6C63FF);
        tv.setTypeface(null,android.graphics.Typeface.BOLD); return tv;
    }
    private void loadImg(final String urlStr, final ImageView tgt) {
        new Thread(new Runnable() {
            @Override public void run() {
                try {
                    HttpURLConnection c=(HttpURLConnection)new URL(urlStr).openConnection();
                    c.setConnectTimeout(5000); c.setReadTimeout(8000);
                    c.setRequestProperty("User-Agent","Mozilla/5.0");
                    final Bitmap bmp=BitmapFactory.decodeStream(c.getInputStream());
                    if(bmp!=null) new Handler(Looper.getMainLooper()).post(new Runnable(){
                        @Override public void run(){if(tgt!=null)tgt.setImageBitmap(bmp);}});
                } catch(Throwable ignored){}
            }
        }).start();
    }
    static String s(Map<String,Object> m,String k){Object v=m.get(k);return(v instanceof String)?(String)v:"";}
    int dp(int v){return Math.round(v*ctx.getResources().getDisplayMetrics().density);}

    static class VH extends RecyclerView.ViewHolder {
        View root; ImageView logo; TextView letter, title, subtitle;
        VH(View r,ImageView lg,TextView lt,TextView ti,TextView su){
            super(r);root=r;logo=lg;letter=lt;title=ti;subtitle=su;}
    }
}
CONTENTEOF
sed -i "s/PACKAGE_PLACEHOLDER/${PACKAGE_NAME}/g" "app/src/main/java/$PKG_PATH/ContentAdapter.java"
echo "ContentAdapter.java OK"

# ══════════════════════════════════════════════════════
# M3uParser.java
# ══════════════════════════════════════════════════════
cat > "app/src/main/java/$PKG_PATH/M3uParser.java" << 'M3UEOF'
package PACKAGE_PLACEHOLDER;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.StringReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class M3uParser {

    public static class Channel {
        public String name="",url="",logo="",group="",referer="",origin="";
        public Map<String,Object> toMap(){
            Map<String,Object> m=new HashMap<>();
            m.put("name",name);m.put("url",url);m.put("logo",logo);
            m.put("group",group);m.put("referer",referer);m.put("origin",origin);
            m.put("active",true);return m;
        }
    }

    public static List<Channel> parseFromUrl(String u) throws Exception {
        HttpURLConnection c=(HttpURLConnection)new URL(u).openConnection();
        c.setConnectTimeout(15000);c.setReadTimeout(30000);
        c.setRequestProperty("User-Agent","VLC/3.0 LibVLC/3.0");
        return parse(new BufferedReader(new InputStreamReader(c.getInputStream())));
    }

    private static List<Channel> parse(BufferedReader r) throws Exception {
        List<Channel> list=new ArrayList<>();
        Channel cur=null; String line;
        while((line=r.readLine())!=null){
            line=line.trim();
            if(line.isEmpty()||line.equals("#EXTM3U")) continue;
            if(line.startsWith("#EXTINF:")){
                cur=new Channel();
                int ci=line.lastIndexOf(',');
                if(ci>=0&&ci<line.length()-1) cur.name=line.substring(ci+1).trim();
                cur.logo=attr(line,"tvg-logo"); cur.group=attr(line,"group-title");
                String tn=attr(line,"tvg-name"); if(!tn.isEmpty()&&cur.name.isEmpty()) cur.name=tn;
            } else if(line.startsWith("#EXTVLCOPT:")){
                if(cur!=null){
                    String opt=line.substring("#EXTVLCOPT:".length()).trim();
                    if(opt.startsWith("http-referrer=")) cur.referer=opt.substring("http-referrer=".length()).trim();
                    else if(opt.startsWith("http-origin=")) cur.origin=opt.substring("http-origin=".length()).trim();
                }
            } else if(!line.startsWith("#")){
                if(cur==null) cur=new Channel();
                cur.url=line;
                if(cur.name.isEmpty()) cur.name=nameFrom(line);
                list.add(cur); cur=null;
            }
        }
        r.close(); return list;
    }

    private static String attr(String txt,String key){
        for(String q:new String[]{"\"","'"}){
            String k=key+"="+q;
            int i=txt.toLowerCase().indexOf(k.toLowerCase());
            if(i>=0){int s=i+k.length(),e=txt.indexOf(q,s);if(e>=0)return txt.substring(s,e).trim();}
        }
        return "";
    }
    private static String nameFrom(String url){
        try{String p=new URL(url).getPath();String[]ps=p.split("/");
            if(ps.length>0){String l=ps[ps.length-1];int d=l.lastIndexOf('.');if(d>0)l=l.substring(0,d);return l.replace("-"," ").replace("_"," ");}}
        catch(Throwable ignored){}
        return "Channel";
    }
}
M3UEOF
sed -i "s/PACKAGE_PLACEHOLDER/${PACKAGE_NAME}/g" "app/src/main/java/$PKG_PATH/M3uParser.java"
echo "M3uParser.java OK"

# ══════════════════════════════════════════════════════
# AdManager.java
# ══════════════════════════════════════════════════════
cat > "app/src/main/java/$PKG_PATH/AdManager.java" << 'ADEOF'
package PACKAGE_PLACEHOLDER;

import android.app.Activity;
import android.util.Log;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import java.util.List;
import java.util.Map;

public class AdManager {

    private static final String TAG = "AdManager";
    private final Activity ctx;
    private Map<String,Object> cfg;
    private boolean inited = false;

    private int admobInterN = 0;
    private int unityInterN = 0;
    private int aplInterN   = 0;

    private Object admobBanner;
    private Object admobInter;

    public AdManager(Activity a) { this.ctx = a; }

    public void init(Map<String,Object> adsCfg, FrameLayout bannerHolder) {
        if (adsCfg == null || inited) return;
        inited = true;
        cfg = adsCfg;
        if (Boolean.TRUE.equals(cfg.get("admobEnabled")))   initAdmob(bannerHolder);
        if (Boolean.TRUE.equals(cfg.get("unityEnabled")))   initUnity();
        if (Boolean.TRUE.equals(cfg.get("aplEnabled")))     initApplovin();
    }

    // ── AdMob ─────────────────────────────────────────────────
    private void initAdmob(final FrameLayout bh) {
        try {
            com.google.android.gms.ads.MobileAds.initialize(ctx,
                is -> Log.d(TAG,"AdMob OK"));
            final String banId = s("admobBanner");
            final String intId = s("admobInter");
            final String pos   = s("admobBanPos");
            ctx.runOnUiThread(new Runnable() {
                @Override public void run() {
                    try {
                        if (!banId.isEmpty() && bh != null) {
                            com.google.android.gms.ads.AdView av =
                                new com.google.android.gms.ads.AdView(ctx);
                            av.setAdUnitId(banId);
                            av.setAdSize(com.google.android.gms.ads.AdSize.BANNER);
                            FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(
                                ViewGroup.LayoutParams.MATCH_PARENT,
                                ViewGroup.LayoutParams.WRAP_CONTENT);
                            lp.gravity = "top".equals(pos) ? Gravity.TOP : Gravity.BOTTOM;
                            bh.addView(av, lp);
                            av.loadAd(new com.google.android.gms.ads.AdRequest.Builder().build());
                            admobBanner = av;
                        }
                        if (!intId.isEmpty()) loadAdmobInter(intId);
                    } catch (Throwable t) { Log.e(TAG,"AdMob UI: "+t); }
                }
            });
        } catch (Throwable t) { Log.e(TAG,"AdMob init: "+t); }
    }

    private void loadAdmobInter(final String id) {
        try {
            com.google.android.gms.ads.interstitial.InterstitialAd.load(ctx, id,
                new com.google.android.gms.ads.AdRequest.Builder().build(),
                new com.google.android.gms.ads.interstitial.InterstitialAdLoadCallback() {
                    @Override public void onAdLoaded(com.google.android.gms.ads.interstitial.InterstitialAd ad) {
                        admobInter = ad; Log.d(TAG,"AdMob inter loaded");
                    }
                    @Override public void onAdFailedToLoad(com.google.android.gms.ads.LoadAdError e) {
                        admobInter = null;
                    }
                });
        } catch (Throwable t) { Log.e(TAG,"AdMob inter load: "+t); }
    }

    // ── Unity ─────────────────────────────────────────────────
    private void initUnity() {
        try {
            String gameId = s("unityGame");
            if (gameId.isEmpty()) return;
            final String intId = s("unityInter");
            com.unity3d.ads.UnityAds.initialize(ctx, gameId, false,
                new com.unity3d.ads.IUnityAdsInitializationListener() {
                    @Override public void onInitializationComplete() {
                        Log.d(TAG,"Unity OK");
                        if (!intId.isEmpty()) {
                            com.unity3d.ads.UnityAds.load(intId,
                                new com.unity3d.ads.IUnityAdsLoadListener() {
                                    @Override public void onUnityAdsAdLoaded(String i) {}
                                    @Override public void onUnityAdsFailedToLoad(String i,
                                        com.unity3d.ads.UnityAds.UnityAdsLoadError e, String m){}
                                });
                        }
                    }
                    @Override public void onInitializationFailed(
                        com.unity3d.ads.UnityAds.UnityAdsInitializationError e, String m){
                        Log.e(TAG,"Unity fail: "+m);
                    }
                });
        } catch (Throwable t) { Log.e(TAG,"Unity init: "+t); }
    }

    // ── AppLovin ──────────────────────────────────────────────
    private void initApplovin() {
        try {
            String key = s("aplKey");
            if (key.isEmpty()) return;
            final String intId = s("aplInter");
            com.applovin.sdk.AppLovinSdk sdk = com.applovin.sdk.AppLovinSdk.getInstance(
                key, new com.applovin.sdk.AppLovinSdkSettings(ctx), ctx);
            sdk.initializeSdk(c -> {
                Log.d(TAG,"AppLovin OK");
                if (!intId.isEmpty()) {
                    ctx.runOnUiThread(new Runnable() {
                        @Override public void run() {
                            try {
                                new com.applovin.mediation.ads.MaxInterstitialAd(intId, ctx).loadAd();
                            } catch (Throwable t) { Log.e(TAG,"APL inter: "+t); }
                        }
                    });
                }
            });
        } catch (Throwable t) { Log.e(TAG,"AppLovin init: "+t); }
    }

    // ── Geçiş reklamı ─────────────────────────────────────────
    public void onTabChange(String tabTitle) {
        if (cfg == null) return;
        try {
            Object excl = cfg.get("excludedSections");
            if (excl instanceof List && ((List<?>)excl).contains(tabTitle)) return;

            // AdMob
            int aFreq = n(s("admobIntFreq"));
            if (aFreq > 0 && admobInter != null) {
                admobInterN++;
                if (admobInterN % aFreq == 0) {
                    try {
                        ((com.google.android.gms.ads.interstitial.InterstitialAd)admobInter).show(ctx);
                        admobInter = null;
                        String id = s("admobInter");
                        if (!id.isEmpty()) loadAdmobInter(id);
                    } catch (Throwable t) { Log.e(TAG,"AdMob show: "+t); }
                    return;
                }
            }

            // Unity
            int uFreq = n(s("unityIntFreq"));
            String uid = s("unityInter");
            if (uFreq > 0 && !uid.isEmpty() && com.unity3d.ads.UnityAds.isInitialized()) {
                unityInterN++;
                if (unityInterN % uFreq == 0) {
                    final String fuid = uid;
                    try {
                        com.unity3d.ads.UnityAds.show(ctx, fuid,
                            new com.unity3d.ads.UnityAdsShowOptions(),
                            new com.unity3d.ads.IUnityAdsShowListener() {
                                @Override public void onUnityAdsShowStart(String i) {}
                                @Override public void onUnityAdsShowClick(String i) {}
                                @Override public void onUnityAdsShowComplete(String i,
                                    com.unity3d.ads.UnityAds.UnityAdsShowCompletionState st) {
                                    com.unity3d.ads.UnityAds.load(fuid,
                                        new com.unity3d.ads.IUnityAdsLoadListener() {
                                            @Override public void onUnityAdsAdLoaded(String id2){}
                                            @Override public void onUnityAdsFailedToLoad(String id2,
                                                com.unity3d.ads.UnityAds.UnityAdsLoadError er,String ms){}
                                        });
                                }
                                @Override public void onUnityAdsShowFailure(String i,
                                    com.unity3d.ads.UnityAds.UnityAdsShowError e,String m){}
                            });
                    } catch (Throwable t) { Log.e(TAG,"Unity show: "+t); }
                }
            }
        } catch (Throwable t) { Log.e(TAG,"onTabChange: "+t); }
    }

    private String s(String k) {
        if (cfg == null) return "";
        Object v = cfg.get(k); return (v instanceof String) ? (String)v : "";
    }
    private int n(String s) {
        try { return Integer.parseInt(s.trim()); } catch (Throwable e) { return 0; }
    }
    public void destroy() {
        try { if (admobBanner instanceof com.google.android.gms.ads.AdView)
            ((com.google.android.gms.ads.AdView)admobBanner).destroy(); }
        catch (Throwable ignored) {}
    }
}
ADEOF
sed -i "s/PACKAGE_PLACEHOLDER/${PACKAGE_NAME}/g" "app/src/main/java/$PKG_PATH/AdManager.java"
echo "AdManager.java OK"

# ══════════════════════════════════════════════════════
# AppFirebaseMessagingService.java
# ══════════════════════════════════════════════════════
cat > "app/src/main/java/$PKG_PATH/AppFirebaseMessagingService.java" << 'FCMEOF'
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
    @Override
    public void onMessageReceived(RemoteMessage msg) {
        super.onMessageReceived(msg);
        try {
            Map<String,String> d = msg.getData();
            String title    = d.containsKey("title")    ? d.get("title")    : "Bildirim";
            String body     = d.containsKey("body")     ? d.get("body")     : "";
            String imageUrl = d.containsKey("imageUrl") ? d.get("imageUrl") : "";
            String clickUrl = d.containsKey("clickUrl") ? d.get("clickUrl") : "";

            NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                nm.createNotificationChannel(new NotificationChannel(
                    "app_ch", "Bildirimler", NotificationManager.IMPORTANCE_HIGH));
            }

            Intent intent = clickUrl.isEmpty()
                ? new Intent(this, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                : new Intent(Intent.ACTION_VIEW, Uri.parse(clickUrl));

            PendingIntent pi = PendingIntent.getActivity(this, 0, intent,
                PendingIntent.FLAG_ONE_SHOT | PendingIntent.FLAG_IMMUTABLE);

            NotificationCompat.Builder b = new NotificationCompat.Builder(this, "app_ch")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title).setContentText(body)
                .setAutoCancel(true).setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(pi)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(body));

            if (!imageUrl.isEmpty()) {
                try {
                    HttpURLConnection c=(HttpURLConnection)new URL(imageUrl).openConnection();
                    c.setConnectTimeout(5000); c.setReadTimeout(5000); c.connect();
                    Bitmap bmp = BitmapFactory.decodeStream(c.getInputStream());
                    if (bmp != null) {
                        b.setStyle(new NotificationCompat.BigPictureStyle().bigPicture(bmp).setSummaryText(body));
                        b.setLargeIcon(bmp);
                    }
                } catch (Throwable ignored) {}
            }
            nm.notify(1001, b.build());
        } catch (Throwable t) { android.util.Log.e("FCM", "Error: " + t); }
    }
}
FCMEOF
sed -i "s/PACKAGE_PLACEHOLDER/${PACKAGE_NAME}/g" "app/src/main/java/$PKG_PATH/AppFirebaseMessagingService.java"
echo "AppFirebaseMessagingService.java OK"

# ══════════════════════════════════════════════════════
# AndroidManifest.xml
# ══════════════════════════════════════════════════════
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

# ══════════════════════════════════════════════════════
# Resources
# ══════════════════════════════════════════════════════
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
    <style name="AppTheme" parent="android:Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@android:color/black</item>
        <item name="android:windowNoTitle">true</item>
        <item name="android:windowFullscreen">true</item>
    </style>
</resources>
STEOF

# Icons
sudo apt-get install -y -qq imagemagick 2>/dev/null
gi() {
  OUT="app/src/main/res/mipmap-$2/ic_launcher.png"
  if [ -f /tmp/icon_src.png ]; then convert /tmp/icon_src.png -resize $1x$1 "$OUT"
  else convert -size $1x$1 xc:"#1a1a2e" -fill "#6c63ff" -gravity center -pointsize $(($1/3)) -annotate 0 "${APP_NAME:0:1}" "$OUT"
  fi
  cp "$OUT" "app/src/main/res/mipmap-$2/ic_launcher_round.png"
}
[ -n "$ICON_URL" ] && wget -q "$ICON_URL" -O /tmp/icon_src.png 2>/dev/null || true
gi 72 hdpi; gi 48 mdpi; gi 96 xhdpi; gi 144 xxhdpi; gi 192 xxxhdpi

# ══════════════════════════════════════════════════════
# Gradle files
# ══════════════════════════════════════════════════════
cat > gradle.properties << GPEOF
android.useAndroidX=true
android.enableJetifier=false
org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=512m
android.nonTransitiveRClass=true
kotlin.stdlib.default.dependency=false
GPEOF

cat > settings.gradle << SGEOF
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "app"
include ':app'
SGEOF

cat > build.gradle << BGEOF
buildscript {
    repositories { google(); mavenCentral() }
    dependencies {
        classpath 'com.android.tools.build:gradle:7.4.2'
        classpath 'com.google.gms:google-services:4.3.15'
    }
}
BGEOF

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
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
    buildTypes { release { minifyEnabled false } }
    packagingOptions {
        resources {
            excludes += ['META-INF/DEPENDENCIES','META-INF/LICENSE','META-INF/NOTICE',
                         'META-INF/*.kotlin_module','META-INF/AL2.0','META-INF/LGPL2.1']
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
    implementation platform('com.google.firebase:firebase-bom:32.7.4')
    implementation 'com.google.firebase:firebase-firestore'
    implementation 'com.google.firebase:firebase-messaging'
    implementation 'androidx.core:core:1.9.0'
    implementation 'androidx.recyclerview:recyclerview:1.3.0'
    implementation 'androidx.media3:media3-exoplayer:1.2.1'
    implementation 'androidx.media3:media3-exoplayer-hls:1.2.1'
    implementation 'androidx.media3:media3-exoplayer-dash:1.2.1'
    implementation 'androidx.media3:media3-exoplayer-rtsp:1.2.1'
    implementation 'androidx.media3:media3-exoplayer-smoothstreaming:1.2.1'
    implementation 'androidx.media3:media3-ui:1.2.1'
    implementation 'com.google.android.gms:play-services-ads:23.0.0'
    implementation 'com.unity3d.ads:unity-ads:4.9.2'
    implementation 'com.applovin:applovin-sdk:12.4.2'
    implementation 'org.jetbrains.kotlin:kotlin-stdlib:1.8.22'
}
ABEOF

mkdir -p gradle/wrapper
cat > gradle/wrapper/gradle-wrapper.properties << GWEOF
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\\://services.gradle.org/distributions/gradle-${GV}-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
GWEOF

# ══════════════════════════════════════════════════════
# BUILD
# ══════════════════════════════════════════════════════
echo "Building..."
"$GRADLE" assembleRelease --no-daemon --no-configuration-cache 2>&1 | tail -60

APK_IN="$WS/app/build/outputs/apk/release/app-release-unsigned.apk"
APK_OUT="/tmp/${PACKAGE_NAME}_v${VC}.apk"
AAB_OUT="/tmp/${PACKAGE_NAME}_v${VC}.aab"

[ -f "$APK_IN" ] || { echo "APK not found!"; find "$WS/app/build" -name "*.apk" 2>/dev/null; exit 1; }

keytool -genkey -v -keystore /tmp/ks.jks -alias release -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass android -keypass android -dname "CN=App,O=App,C=US" -noprompt 2>/dev/null

"$BUILD_TOOLS/zipalign" -v 4 "$APK_IN" /tmp/aligned.apk
"$BUILD_TOOLS/apksigner" sign --ks /tmp/ks.jks --ks-key-alias release \
  --ks-pass pass:android --key-pass pass:android --out "$APK_OUT" /tmp/aligned.apk

"$GRADLE" bundleRelease --no-daemon --no-configuration-cache 2>&1 | tail -10
AAB_IN="$WS/app/build/outputs/bundle/release/app-release.aab"
[ -f "$AAB_IN" ] && cp "$AAB_IN" "$AAB_OUT" || true

echo "APK_FILE=$APK_OUT" >> $GITHUB_ENV
echo "AAB_FILE=$AAB_OUT" >> $GITHUB_ENV
echo "=== DONE: $(du -sh $APK_OUT 2>/dev/null | cut -f1) ==="
