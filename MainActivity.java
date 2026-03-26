package PACKAGE_PLACEHOLDER;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.*;
import android.widget.*;
import androidx.recyclerview.widget.GridLayoutManager;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.google.firebase.firestore.*;
import com.google.firebase.messaging.FirebaseMessaging;
import java.util.*;

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
    private Map<String,Object>   appConfig    = new HashMap<>();
    private List<Map<String,Object>> menuSections = new ArrayList<>();
    private int    activeMenuIndex = -1;
    private String primaryColor    = "#6c63ff";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,
                             WindowManager.LayoutParams.FLAG_FULLSCREEN);
        buildLayout();
        subscribeFCM();
        listenConfig();
    }

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

        FrameLayout.LayoutParams fill = new FrameLayout.LayoutParams(-1,-1);
        FrameLayout.LayoutParams pb   = new FrameLayout.LayoutParams(-1, dp(4));
        FrameLayout.LayoutParams nav  = new FrameLayout.LayoutParams(-1, dp(58));
        nav.gravity = Gravity.BOTTOM;

        rootLayout.addView(webView, fill);
        rootLayout.addView(contentRecycler, fill);
        rootLayout.addView(progressBar, pb);
        rootLayout.addView(bottomNav, nav);
        setContentView(rootLayout);
    }

    private void subscribeFCM() {
        FirebaseMessaging.getInstance().subscribeToTopic(FCM_TOPIC);
    }

    private void listenConfig() {
        db = FirebaseFirestore.getInstance();
        db.collection("apps").document(OWNER_ID)
          .collection("list").document(APP_ID)
          .addSnapshotListener((snap, err) -> {
              if (err != null || snap == null || !snap.exists()) return;
              appConfig = snap.getData() != null ? snap.getData() : new HashMap<>();
              processConfig(snap);
          });
    }

    @SuppressWarnings("unchecked")
    private void processConfig(DocumentSnapshot snap) {
        // Primary color
        String pc = snap.getString("config.primaryColor");
        if (pc != null && !pc.isEmpty()) primaryColor = pc;
        try { getWindow().setStatusBarColor(Color.parseColor(primaryColor)); } catch(Exception ignored){}

        // Menu
        List<Object> raw = (List<Object>) snap.get("config.menu");
        menuSections.clear();
        if (raw != null) {
            for (Object o : raw) if (o instanceof Map) menuSections.add((Map<String,Object>)o);
        }

        runOnUiThread(() -> {
            buildBottomNav();
            if (activeMenuIndex < 0 && !menuSections.isEmpty()) {
                selectMenu(0);
            } else if (menuSections.isEmpty()) {
                String url = snap.getString("config.contentUrl");
                showWebView(url != null ? url : DEFAULT_URL);
            }
        });
    }

    private void buildBottomNav() {
        bottomNav.removeAllViews();
        if (menuSections.isEmpty()) { bottomNav.setVisibility(View.GONE); return; }
        bottomNav.setVisibility(View.VISIBLE);
        int active, inactive;
        try { active=Color.parseColor(primaryColor); } catch(Exception e){ active=Color.parseColor("#6c63ff"); }
        inactive = Color.parseColor("#6060808");

        for (int i = 0; i < menuSections.size(); i++) {
            final int idx = i;
            Map<String,Object> s = menuSections.get(i);
            String title = strOr(s,"title","");
            String icon  = strOr(s,"icon","▶");
            boolean isActive = (idx == activeMenuIndex);

            LinearLayout item = new LinearLayout(this);
            item.setOrientation(LinearLayout.VERTICAL);
            item.setGravity(Gravity.CENTER);
            item.setLayoutParams(new LinearLayout.LayoutParams(0,-1,1f));
            item.setOnClickListener(v -> selectMenu(idx));
            if (isActive) item.setBackgroundColor(Color.parseColor("#1a1a2e"));

            TextView iv = new TextView(this);
            iv.setText(icon.isEmpty() ? "▶" : icon);
            iv.setTextSize(18); iv.setGravity(Gravity.CENTER);
            iv.setTextColor(isActive ? active : Color.parseColor("#606080"));

            TextView tv = new TextView(this);
            tv.setText(title);
            tv.setTextSize(9); tv.setGravity(Gravity.CENTER);
            tv.setTextColor(isActive ? active : Color.parseColor("#606080"));

            item.addView(iv); item.addView(tv);
            bottomNav.addView(item);
        }
    }

    @SuppressWarnings("unchecked")
    private void selectMenu(int idx) {
        if (idx >= menuSections.size()) return;
        activeMenuIndex = idx;
        buildBottomNav();
        Map<String,Object> section = menuSections.get(idx);
        String type    = strOr(section,"type","web");
        String url     = strOr(section,"url","");
        String display = strOr(section,"display","list");

        switch(type) {
            case "m3u": case "iptv":
                List<Object> rawItems = (List<Object>) section.getOrDefault("items", new ArrayList<>());
                List<Map<String,Object>> items = new ArrayList<>();
                for (Object o : rawItems) if (o instanceof Map) items.add((Map<String,Object>)o);
                showContentList(items, display);
                break;
            case "video":
                openPlayer(url, strOr(section,"title",""), "", "");
                break;
            case "web": default:
                showWebView(url);
                break;
        }
    }

    private void showWebView(String url) {
        webView.setVisibility(View.VISIBLE);
        contentRecycler.setVisibility(View.GONE);
        if (url != null && !url.isEmpty() && !url.equals(webView.getUrl())) {
            progressBar.setVisibility(View.VISIBLE);
            webView.loadUrl(url);
        }
    }

    private void showContentList(List<Map<String,Object>> items, String display) {
        webView.setVisibility(View.GONE);
        contentRecycler.setVisibility(View.VISIBLE);
        boolean isGrid = "grid".equals(display);
        contentRecycler.setLayoutManager(isGrid
            ? new GridLayoutManager(this,3)
            : new LinearLayoutManager(this));
        contentRecycler.setAdapter(new ContentAdapter(this, items, display, primaryColor,
            item -> {
                String url     = strOr(item,"url","");
                String title   = strOr(item,"name","");
                String referer = strOr(item,"referer","");
                String origin  = strOr(item,"origin","");
                openPlayer(url, title, referer, origin);
            }));
    }

    public void openPlayer(String url, String title, String referer, String origin) {
        Intent i = new Intent(this, PlayerActivity.class);
        i.putExtra("url",url); i.putExtra("title",title);
        i.putExtra("referer",referer); i.putExtra("origin",origin);
        startActivity(i);
    }

    static String strOr(Map<String,Object> m, String k, String def) {
        Object v = m.get(k); return (v instanceof String && !((String)v).isEmpty()) ? (String)v : def;
    }
    int dp(int v) { return Math.round(v * getResources().getDisplayMetrics().density); }

    @Override public void onBackPressed() {
        if (webView.getVisibility()==View.VISIBLE && webView.canGoBack()) webView.goBack();
        else super.onBackPressed();
    }
    @Override protected void onDestroy() {
        super.onDestroy();
        if (configListener != null) configListener.remove();
    }
}
