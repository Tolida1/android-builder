package PACKAGE_PLACEHOLDER;

import android.app.Activity;
import android.content.pm.ActivityInfo;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.view.*;
import android.widget.*;
import androidx.media3.common.*;
import androidx.media3.datasource.*;
import androidx.media3.datasource.okhttp.OkHttpDataSource;
import androidx.media3.exoplayer.*;
import androidx.media3.exoplayer.dash.DashMediaSource;
import androidx.media3.exoplayer.hls.HlsMediaSource;
import androidx.media3.exoplayer.rtsp.RtspMediaSource;
import androidx.media3.exoplayer.smoothstreaming.SsMediaSource;
import androidx.media3.exoplayer.source.*;
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector;
import androidx.media3.ui.AspectRatioFrameLayout;
import androidx.media3.ui.PlayerView;
import okhttp3.*;
import java.util.concurrent.TimeUnit;

public class PlayerActivity extends Activity {

    // ── Scale modes (cycle with button) ──────────────────────
    private static final int[] SCALE_MODES = {
        AspectRatioFrameLayout.RESIZE_MODE_FIT,        // Fit (letterbox)
        AspectRatioFrameLayout.RESIZE_MODE_FILL,       // Fill (crop)
        AspectRatioFrameLayout.RESIZE_MODE_FIXED_WIDTH,// Fixed width
        AspectRatioFrameLayout.RESIZE_MODE_ZOOM,       // Zoom
    };
    private static final String[] SCALE_LABELS = {"FIT","FILL","WIDTH","ZOOM"};
    private int scaleModeIdx = 1; // default FILL

    private ExoPlayer    player;
    private PlayerView   playerView;
    private FrameLayout  rootLayout;
    private View         controlsOverlay;
    private TextView     titleTv, timeTv, scaleTv;
    private ImageButton  btnPlay, btnScale, btnBack, btnSpeed, btnLock;
    private SeekBar      seekBar;
    private boolean      controlsVisible  = true;
    private boolean      locked           = false;
    private float        currentSpeed     = 1.0f;
    private final Handler handler          = new Handler();
    private final Runnable hideControls    = () -> { if (!locked) hideControlsAnim(); };

    // Scale gesture
    private ScaleGestureDetector scaleDetector;
    private float currentScaleX = 1f;
    private float currentScaleY = 1f;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,
                             WindowManager.LayoutParams.FLAG_FULLSCREEN);
        getWindow().setDecorFitsSystemWindows(false);
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);

        String url     = getIntent().getStringExtra("url");
        String title   = getIntent().getStringExtra("title");
        String referer = getIntent().getStringExtra("referer");
        String origin  = getIntent().getStringExtra("origin");

        buildLayout(title);
        buildPlayer(url, referer, origin);
        scheduleHideControls();
    }

    // ── Layout ────────────────────────────────────────────────
    private void buildLayout(String title) {
        rootLayout = new FrameLayout(this);
        rootLayout.setBackgroundColor(Color.BLACK);

        // PlayerView
        playerView = new PlayerView(this);
        playerView.setResizeMode(SCALE_MODES[scaleModeIdx]);
        playerView.setUseController(false); // custom controls
        playerView.setKeepScreenOn(true);

        FrameLayout.LayoutParams fill = new FrameLayout.LayoutParams(-1,-1);
        rootLayout.addView(playerView, fill);

        // Gesture overlay (tap + pinch zoom)
        View gestureView = new View(this);
        gestureView.setLayoutParams(fill);

        scaleDetector = new ScaleGestureDetector(this, new ScaleGestureDetector.SimpleOnScaleGestureListener() {
            @Override public boolean onScale(ScaleGestureDetector d) {
                float factor = d.getScaleFactor();
                currentScaleX = Math.max(0.5f, Math.min(currentScaleX * factor, 4f));
                currentScaleY = currentScaleX;
                playerView.setScaleX(currentScaleX);
                playerView.setScaleY(currentScaleY);
                return true;
            }
        });

        GestureDetector tapDetector = new GestureDetector(this, new GestureDetector.SimpleOnGestureListener() {
            @Override public boolean onSingleTapUp(MotionEvent e) {
                toggleControls(); return true;
            }
            @Override public boolean onDoubleTap(MotionEvent e) {
                // Double tap: reset zoom
                currentScaleX = 1f; currentScaleY = 1f;
                playerView.setScaleX(1f); playerView.setScaleY(1f);
                return true;
            }
            @Override public boolean onFling(MotionEvent e1, MotionEvent e2, float vx, float vy) {
                if (Math.abs(vy) > Math.abs(vx)) {
                    // Swipe up/down: brightness or volume (simplified)
                    return true;
                }
                return false;
            }
        });

        gestureView.setOnTouchListener((v, e) -> {
            scaleDetector.onTouchEvent(e);
            tapDetector.onTouchEvent(e);
            return true;
        });
        rootLayout.addView(gestureView, fill);

        // Controls overlay
        controlsOverlay = buildControlsOverlay(title);
        rootLayout.addView(controlsOverlay, fill);

        setContentView(rootLayout);
    }

    private View buildControlsOverlay(String title) {
        FrameLayout overlay = new FrameLayout(this);

        // Top bar
        LinearLayout topBar = new LinearLayout(this);
        topBar.setOrientation(LinearLayout.HORIZONTAL);
        topBar.setBackgroundColor(Color.parseColor("#AA000000"));
        topBar.setPadding(dp(12), dp(8), dp(12), dp(8));
        topBar.setGravity(Gravity.CENTER_VERTICAL);
        FrameLayout.LayoutParams topParams = new FrameLayout.LayoutParams(-1,-2);
        topParams.gravity = Gravity.TOP;

        btnBack = new ImageButton(this);
        btnBack.setText("←");
        btnBack.setTextSize(20);
        btnBack.setBackgroundColor(Color.TRANSPARENT);
        btnBack.setTextColor(Color.WHITE);
        btnBack.setOnClickListener(v -> finish());
        // Use TextView styled as button
        TextView backBtn = new TextView(this);
        backBtn.setText("←");
        backBtn.setTextSize(22);
        backBtn.setTextColor(Color.WHITE);
        backBtn.setPadding(0,0,dp(16),0);
        backBtn.setOnClickListener(v -> finish());

        titleTv = new TextView(this);
        titleTv.setText(title != null ? title : "");
        titleTv.setTextSize(15);
        titleTv.setTextColor(Color.WHITE);
        titleTv.setMaxLines(1);
        titleTv.setEllipsize(android.text.TextUtils.TruncateAt.END);
        LinearLayout.LayoutParams titleLP = new LinearLayout.LayoutParams(0,-2,1f);
        titleTv.setLayoutParams(titleLP);

        scaleTv = new TextView(this);
        scaleTv.setText(SCALE_LABELS[scaleModeIdx]);
        scaleTv.setTextSize(12);
        scaleTv.setTextColor(Color.parseColor("#aaaaff"));
        scaleTv.setPadding(dp(8),dp(4),dp(8),dp(4));
        scaleTv.setBackgroundColor(Color.parseColor("#441a1a2e"));
        scaleTv.setOnClickListener(v -> cycleScaleMode());

        topBar.addView(backBtn);
        topBar.addView(titleTv);
        topBar.addView(scaleTv);
        overlay.addView(topBar, topParams);

        // Bottom controls
        LinearLayout bottomBar = new LinearLayout(this);
        bottomBar.setOrientation(LinearLayout.VERTICAL);
        bottomBar.setBackgroundColor(Color.parseColor("#AA000000"));
        bottomBar.setPadding(dp(12), dp(8), dp(12), dp(12));
        FrameLayout.LayoutParams botParams = new FrameLayout.LayoutParams(-1,-2);
        botParams.gravity = Gravity.BOTTOM;

        // Seek row
        LinearLayout seekRow = new LinearLayout(this);
        seekRow.setOrientation(LinearLayout.HORIZONTAL);
        seekRow.setGravity(Gravity.CENTER_VERTICAL);

        timeTv = new TextView(this);
        timeTv.setText("0:00 / 0:00");
        timeTv.setTextSize(11);
        timeTv.setTextColor(Color.WHITE);
        timeTv.setMinWidth(dp(90));

        seekBar = new SeekBar(this);
        seekBar.setProgressTintList(android.content.res.ColorStateList.valueOf(Color.parseColor("#6c63ff")));
        seekBar.setThumbTintList(android.content.res.ColorStateList.valueOf(Color.WHITE));
        LinearLayout.LayoutParams seekLP = new LinearLayout.LayoutParams(0,-2,1f);
        seekBar.setLayoutParams(seekLP);
        seekBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar s, int p, boolean user) {
                if (user && player != null) player.seekTo((long)p * 1000);
            }
            @Override public void onStartTrackingTouch(SeekBar s) { handler.removeCallbacks(hideControls); }
            @Override public void onStopTrackingTouch(SeekBar s) { scheduleHideControls(); }
        });

        seekRow.addView(timeTv);
        seekRow.addView(seekBar);

        // Button row
        LinearLayout btnRow = new LinearLayout(this);
        btnRow.setOrientation(LinearLayout.HORIZONTAL);
        btnRow.setGravity(Gravity.CENTER);
        btnRow.setPadding(0,dp(8),0,0);

        // Rewind 10s
        TextView rw = makeCtrlBtn("«10");
        rw.setOnClickListener(v -> { if(player!=null) player.seekTo(Math.max(0,player.getCurrentPosition()-10000)); });

        // Play/Pause
        btnPlay = new ImageButton(this);
        btnPlay.setBackgroundColor(Color.TRANSPARENT);
        TextView playBtn = makeCtrlBtn("⏸");
        playBtn.setTextSize(24);
        playBtn.setOnClickListener(v -> {
            if(player==null) return;
            if(player.isPlaying()){ player.pause(); playBtn.setText("▶"); }
            else { player.play(); playBtn.setText("⏸"); }
            scheduleHideControls();
        });
        // Keep reference
        playBtn.setTag("play");

        // Forward 10s
        TextView fw = makeCtrlBtn("10»");
        fw.setOnClickListener(v -> { if(player!=null) player.seekTo(player.getCurrentPosition()+10000); });

        // Speed
        TextView speedBtn = makeCtrlBtn("1x");
        float[] speeds = {0.5f,0.75f,1.0f,1.25f,1.5f,2.0f};
        String[] speedLabels = {"0.5x","0.75x","1x","1.25x","1.5x","2x"};
        final int[] speedIdx = {2};
        speedBtn.setOnClickListener(v -> {
            speedIdx[0] = (speedIdx[0]+1) % speeds.length;
            currentSpeed = speeds[speedIdx[0]];
            speedBtn.setText(speedLabels[speedIdx[0]]);
            if(player!=null) player.setPlaybackSpeed(currentSpeed);
        });

        // Aspect / Scale
        TextView scaleBtn = makeCtrlBtn("⊡");
        scaleBtn.setOnClickListener(v -> cycleScaleMode());

        // Zoom reset
        TextView zoomReset = makeCtrlBtn("1:1");
        zoomReset.setOnClickListener(v -> {
            currentScaleX=1f; currentScaleY=1f;
            playerView.setScaleX(1f); playerView.setScaleY(1f);
        });

        // Lock (hide controls)
        TextView lockBtn = makeCtrlBtn("🔓");
        lockBtn.setOnClickListener(v -> {
            locked = !locked;
            lockBtn.setText(locked ? "🔒" : "🔓");
            if(locked) hideControlsAnim();
        });

        btnRow.addView(rw);
        btnRow.addView(playBtn);
        btnRow.addView(fw);
        btnRow.addView(speedBtn);
        btnRow.addView(scaleBtn);
        btnRow.addView(zoomReset);
        btnRow.addView(lockBtn);

        bottomBar.addView(seekRow);
        bottomBar.addView(btnRow);
        overlay.addView(bottomBar, botParams);

        // Update seek bar periodically
        handler.post(new Runnable() {
            @Override public void run() {
                if (player != null && player.getDuration() > 0) {
                    long pos = player.getCurrentPosition();
                    long dur = player.getDuration();
                    seekBar.setMax((int)(dur/1000));
                    seekBar.setProgress((int)(pos/1000));
                    timeTv.setText(fmtTime(pos) + " / " + fmtTime(dur));
                }
                handler.postDelayed(this, 500);
            }
        });

        return overlay;
    }

    // ── Build Player ──────────────────────────────────────────
    private void buildPlayer(String url, String referer, String origin) {
        if (url == null || url.isEmpty()) { finish(); return; }

        DefaultTrackSelector trackSelector = new DefaultTrackSelector(this);
        trackSelector.setParameters(trackSelector.buildUponParameters()
            .setPreferredAudioLanguage("tr")
            .build());

        player = new ExoPlayer.Builder(this)
            .setTrackSelector(trackSelector)
            .build();
        playerView.setPlayer(player);

        // HTTP headers (referer + origin)
        DataSource.Factory dsFactory = buildDataSourceFactory(referer, origin);

        // Detect format and build media source
        MediaSource mediaSource = buildMediaSource(url, dsFactory);
        player.setMediaSource(mediaSource);
        player.prepare();
        player.setPlayWhenReady(true);
        player.setPlaybackSpeed(currentSpeed);

        player.addListener(new Player.Listener() {
            @Override public void onIsPlayingChanged(boolean playing) {
                // update play button
                View playBtn = controlsOverlay.findViewWithTag("play");
                if (playBtn instanceof TextView) ((TextView)playBtn).setText(playing ? "⏸" : "▶");
            }
            @Override public void onPlayerError(PlaybackException error) {
                Toast.makeText(PlayerActivity.this, "Oynatma hatası: "+error.getMessage(), Toast.LENGTH_SHORT).show();
            }
        });
    }

    private DataSource.Factory buildDataSourceFactory(String referer, String origin) {
        OkHttpClient.Builder clientBuilder = new OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS);

        if ((referer != null && !referer.isEmpty()) || (origin != null && !origin.isEmpty())) {
            final String ref = referer;
            final String ori = origin;
            clientBuilder.addInterceptor(chain -> {
                Request.Builder reqBuilder = chain.request().newBuilder();
                if (ref != null && !ref.isEmpty()) reqBuilder.header("Referer", ref);
                if (ori != null && !ori.isEmpty()) reqBuilder.header("Origin", ori);
                reqBuilder.header("User-Agent", "Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/110.0.0.0 Mobile Safari/537.36");
                return chain.proceed(reqBuilder.build());
            });
        }

        return new OkHttpDataSource.Factory(clientBuilder.build());
    }

    private MediaSource buildMediaSource(String url, DataSource.Factory dsFactory) {
        Uri uri = Uri.parse(url);
        String lower = url.toLowerCase();

        // DASH
        if (lower.contains(".mpd") || lower.contains("dash")) {
            return new DashMediaSource.Factory(dsFactory).createMediaSource(MediaItem.fromUri(uri));
        }
        // HLS
        if (lower.contains(".m3u8") || lower.contains("m3u8")) {
            return new HlsMediaSource.Factory(dsFactory).createMediaSource(MediaItem.fromUri(uri));
        }
        // RTSP
        if (lower.startsWith("rtsp://")) {
            return new RtspMediaSource.Factory().createMediaSource(MediaItem.fromUri(uri));
        }
        // SmoothStreaming
        if (lower.contains(".ism") || lower.contains("smoothstreaming")) {
            return new SsMediaSource.Factory(dsFactory).createMediaSource(MediaItem.fromUri(uri));
        }
        // Progressive (MP4, MKV, AVI, etc) + fallback HLS for .m3u
        if (lower.endsWith(".m3u")) {
            return new HlsMediaSource.Factory(dsFactory).createMediaSource(MediaItem.fromUri(uri));
        }
        // Default: progressive
        return new ProgressiveMediaSource.Factory(dsFactory).createMediaSource(MediaItem.fromUri(uri));
    }

    // ── Scale Mode ────────────────────────────────────────────
    private void cycleScaleMode() {
        scaleModeIdx = (scaleModeIdx + 1) % SCALE_MODES.length;
        playerView.setResizeMode(SCALE_MODES[scaleModeIdx]);
        scaleTv.setText(SCALE_LABELS[scaleModeIdx]);
    }

    // ── Controls visibility ───────────────────────────────────
    private void toggleControls() {
        if (locked) return;
        if (controlsVisible) hideControlsAnim();
        else showControlsAnim();
    }
    private void showControlsAnim() {
        controlsVisible = true;
        controlsOverlay.animate().alpha(1f).setDuration(200).start();
        scheduleHideControls();
    }
    private void hideControlsAnim() {
        controlsVisible = false;
        controlsOverlay.animate().alpha(0f).setDuration(300).start();
    }
    private void scheduleHideControls() {
        handler.removeCallbacks(hideControls);
        handler.postDelayed(hideControls, 4000);
    }

    // ── Helpers ───────────────────────────────────────────────
    private TextView makeCtrlBtn(String label) {
        TextView tv = new TextView(this);
        tv.setText(label);
        tv.setTextSize(14);
        tv.setTextColor(Color.WHITE);
        tv.setPadding(dp(12),dp(6),dp(12),dp(6));
        tv.setGravity(Gravity.CENTER);
        tv.setOnClickListener(v -> scheduleHideControls());
        return tv;
    }
    private String fmtTime(long ms) {
        long s=ms/1000; long m=s/60; s=s%60;
        long h=m/60; m=m%60;
        if(h>0) return String.format("%d:%02d:%02d",h,m,s);
        return String.format("%d:%02d",m,s);
    }
    int dp(int v) { return Math.round(v * getResources().getDisplayMetrics().density); }

    @Override protected void onStop()    { super.onStop(); if(player!=null) player.pause(); }
    @Override protected void onDestroy() {
        super.onDestroy();
        handler.removeCallbacksAndMessages(null);
        if(player!=null){ player.release(); player=null; }
    }
    @Override public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if(hasFocus) getWindow().getDecorView().setSystemUiVisibility(
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY|View.SYSTEM_UI_FLAG_HIDE_NAVIGATION|View.SYSTEM_UI_FLAG_FULLSCREEN);
    }
}
