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
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.datasource.DataSource;
import androidx.media3.datasource.okhttp.OkHttpDataSource;
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
import okhttp3.Interceptor;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import java.io.IOException;
import java.util.concurrent.TimeUnit;

public class PlayerActivity extends Activity {

    private static final int[] SCALE_MODES = {
        AspectRatioFrameLayout.RESIZE_MODE_FILL,
        AspectRatioFrameLayout.RESIZE_MODE_FIT,
        AspectRatioFrameLayout.RESIZE_MODE_ZOOM,
        AspectRatioFrameLayout.RESIZE_MODE_FIXED_WIDTH,
    };
    private static final String[] SCALE_LABELS = {"FILL","FIT","ZOOM","WIDTH"};
    private int scaleModeIdx = 0;

    private ExoPlayer   player;
    private PlayerView  playerView;
    private View        controlsOverlay;
    private TextView    titleTv, timeTv, scaleTv, playTv;
    private SeekBar     seekBar;
    private boolean     controlsVisible = true;
    private boolean     locked          = false;
    private float       currentSpeed    = 1.0f;
    private final Handler  handler      = new Handler();
    private final Runnable hideCtrl     = new Runnable() {
        @Override public void run() { if (!locked) hideAnim(); }
    };
    private ScaleGestureDetector scaleDetector;
    private GestureDetector      tapDetector;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(
            WindowManager.LayoutParams.FLAG_FULLSCREEN,
            WindowManager.LayoutParams.FLAG_FULLSCREEN);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);

        String url     = getIntent().getStringExtra("url");
        String title   = getIntent().getStringExtra("title");
        String referer = getIntent().getStringExtra("referer");
        String origin  = getIntent().getStringExtra("origin");

        buildLayout(title != null ? title : "");
        buildPlayer(url, referer != null ? referer : "", origin != null ? origin : "");
        scheduleHide();
    }

    private void buildLayout(String title) {
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);

        playerView = new PlayerView(this);
        playerView.setResizeMode(SCALE_MODES[scaleModeIdx]);
        playerView.setUseController(false);
        playerView.setKeepScreenOn(true);
        root.addView(playerView, new FrameLayout.LayoutParams(-1, -1));

        // Gesture layer
        View gl = new View(this);
        scaleDetector = new ScaleGestureDetector(this,
            new ScaleGestureDetector.SimpleOnScaleGestureListener() {
                @Override public boolean onScale(ScaleGestureDetector d) {
                    float f = d.getScaleFactor();
                    float sx = Math.max(0.5f, Math.min(playerView.getScaleX() * f, 4f));
                    playerView.setScaleX(sx);
                    playerView.setScaleY(sx);
                    return true;
                }
            });
        tapDetector = new GestureDetector(this,
            new GestureDetector.SimpleOnGestureListener() {
                @Override public boolean onSingleTapUp(MotionEvent e) {
                    toggleCtrl(); return true;
                }
                @Override public boolean onDoubleTap(MotionEvent e) {
                    playerView.setScaleX(1f); playerView.setScaleY(1f); return true;
                }
            });
        gl.setOnTouchListener(new View.OnTouchListener() {
            @Override public boolean onTouch(View v, MotionEvent e) {
                scaleDetector.onTouchEvent(e);
                tapDetector.onTouchEvent(e);
                return true;
            }
        });
        root.addView(gl, new FrameLayout.LayoutParams(-1, -1));

        // Controls overlay
        controlsOverlay = buildControls(root, title);
        setContentView(root);

        // Seek update
        handler.post(new Runnable() {
            @Override public void run() {
                if (player != null && player.getDuration() > 0) {
                    long pos = player.getCurrentPosition();
                    long dur = player.getDuration();
                    seekBar.setMax((int)(dur / 1000));
                    seekBar.setProgress((int)(pos / 1000));
                    timeTv.setText(fmt(pos) + " / " + fmt(dur));
                }
                handler.postDelayed(this, 500);
            }
        });
    }

    private View buildControls(FrameLayout root, String title) {
        FrameLayout overlay = new FrameLayout(this);

        // Top bar
        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setBackgroundColor(Color.parseColor("#BB000000"));
        top.setPadding(dp(12), dp(10), dp(12), dp(10));
        top.setGravity(Gravity.CENTER_VERTICAL);
        FrameLayout.LayoutParams tp = new FrameLayout.LayoutParams(-1, -2);
        tp.gravity = Gravity.TOP;

        TextView back = new TextView(this);
        back.setText("←");
        back.setTextSize(22); back.setTextColor(Color.WHITE);
        back.setPadding(0, 0, dp(14), 0);
        back.setOnClickListener(v -> finish());

        titleTv = new TextView(this);
        titleTv.setText(title);
        titleTv.setTextSize(14); titleTv.setTextColor(Color.WHITE);
        titleTv.setMaxLines(1);
        titleTv.setEllipsize(android.text.TextUtils.TruncateAt.END);
        titleTv.setLayoutParams(new LinearLayout.LayoutParams(0, -2, 1f));

        scaleTv = new TextView(this);
        scaleTv.setText(SCALE_LABELS[scaleModeIdx]);
        scaleTv.setTextSize(11); scaleTv.setTextColor(Color.parseColor("#aaaaff"));
        scaleTv.setPadding(dp(8), dp(4), dp(8), dp(4));
        scaleTv.setBackgroundColor(Color.parseColor("#441a1a2e"));
        scaleTv.setOnClickListener(v -> { cycleScale(); scheduleHide(); });

        top.addView(back); top.addView(titleTv); top.addView(scaleTv);
        overlay.addView(top, tp);

        // Bottom bar
        LinearLayout bot = new LinearLayout(this);
        bot.setOrientation(LinearLayout.VERTICAL);
        bot.setBackgroundColor(Color.parseColor("#BB000000"));
        bot.setPadding(dp(12), dp(8), dp(12), dp(12));
        FrameLayout.LayoutParams bp = new FrameLayout.LayoutParams(-1, -2);
        bp.gravity = Gravity.BOTTOM;

        // Seek row
        LinearLayout seekRow = new LinearLayout(this);
        seekRow.setOrientation(LinearLayout.HORIZONTAL);
        seekRow.setGravity(Gravity.CENTER_VERTICAL);

        timeTv = new TextView(this);
        timeTv.setText("0:00 / 0:00");
        timeTv.setTextSize(11); timeTv.setTextColor(Color.WHITE);
        timeTv.setMinWidth(dp(90));

        seekBar = new SeekBar(this);
        seekBar.setProgressTintList(android.content.res.ColorStateList.valueOf(Color.parseColor("#6c63ff")));
        seekBar.setThumbTintList(android.content.res.ColorStateList.valueOf(Color.WHITE));
        seekBar.setLayoutParams(new LinearLayout.LayoutParams(0, -2, 1f));
        seekBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar s, int p, boolean user) {
                if (user && player != null) player.seekTo((long) p * 1000);
            }
            @Override public void onStartTrackingTouch(SeekBar s) { handler.removeCallbacks(hideCtrl); }
            @Override public void onStopTrackingTouch(SeekBar s) { scheduleHide(); }
        });
        seekRow.addView(timeTv); seekRow.addView(seekBar);

        // Button row
        LinearLayout btnRow = new LinearLayout(this);
        btnRow.setOrientation(LinearLayout.HORIZONTAL);
        btnRow.setGravity(Gravity.CENTER);
        btnRow.setPadding(0, dp(8), 0, 0);

        // Rewind
        TextView rw = ctrlBtn("«10");
        rw.setOnClickListener(v -> { if(player!=null) player.seekTo(Math.max(0,player.getCurrentPosition()-10000)); scheduleHide(); });

        // Play/Pause
        playTv = ctrlBtn("⏸");
        playTv.setTextSize(24);
        playTv.setOnClickListener(v -> {
            if (player == null) return;
            if (player.isPlaying()) { player.pause(); playTv.setText("▶"); }
            else                    { player.play();  playTv.setText("⏸"); }
            scheduleHide();
        });

        // Forward
        TextView fw = ctrlBtn("10»");
        fw.setOnClickListener(v -> { if(player!=null) player.seekTo(player.getCurrentPosition()+10000); scheduleHide(); });

        // Speed
        final float[] speeds = {0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f};
        final String[] spLbls = {"0.5x","0.75x","1x","1.25x","1.5x","2x"};
        final int[] spIdx = {2};
        TextView speedTv = ctrlBtn("1x");
        speedTv.setOnClickListener(v -> {
            spIdx[0] = (spIdx[0] + 1) % speeds.length;
            currentSpeed = speeds[spIdx[0]];
            speedTv.setText(spLbls[spIdx[0]]);
            if (player != null) player.setPlaybackSpeed(currentSpeed);
            scheduleHide();
        });

        // Zoom reset
        TextView zoomReset = ctrlBtn("1:1");
        zoomReset.setOnClickListener(v -> { playerView.setScaleX(1f); playerView.setScaleY(1f); scheduleHide(); });

        // Lock
        final TextView lockTv = ctrlBtn("🔓");
        lockTv.setOnClickListener(v -> {
            locked = !locked;
            lockTv.setText(locked ? "🔒" : "🔓");
            if (locked) hideAnim();
        });

        btnRow.addView(rw); btnRow.addView(playTv); btnRow.addView(fw);
        btnRow.addView(speedTv); btnRow.addView(scaleTv); btnRow.addView(zoomReset); btnRow.addView(lockTv);

        bot.addView(seekRow); bot.addView(btnRow);
        overlay.addView(bot, bp);
        root.addView(overlay, new FrameLayout.LayoutParams(-1, -1));
        return overlay;
    }

    private void buildPlayer(String url, String referer, String origin) {
        if (url == null || url.isEmpty()) { finish(); return; }

        DefaultTrackSelector ts = new DefaultTrackSelector(this);
        player = new ExoPlayer.Builder(this).setTrackSelector(ts).build();
        playerView.setPlayer(player);

        OkHttpClient.Builder cb = new OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS);

        final String ref = referer;
        final String ori = origin;
        if (!ref.isEmpty() || !ori.isEmpty()) {
            cb.addInterceptor(new Interceptor() {
                @Override public okhttp3.Response intercept(Chain chain) throws IOException {
                    Request.Builder rb = chain.request().newBuilder()
                        .header("User-Agent","Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/110.0.0.0 Mobile Safari/537.36");
                    if (!ref.isEmpty()) rb.header("Referer", ref);
                    if (!ori.isEmpty()) rb.header("Origin",  ori);
                    return chain.proceed(rb.build());
                }
            });
        }

        DataSource.Factory dsf = new OkHttpDataSource.Factory(cb.build());
        MediaSource ms = buildSource(url, dsf);
        player.setMediaSource(ms);
        player.prepare();
        player.setPlayWhenReady(true);
        player.setPlaybackSpeed(currentSpeed);

        player.addListener(new Player.Listener() {
            @Override public void onIsPlayingChanged(boolean playing) {
                if (playTv != null) playTv.setText(playing ? "⏸" : "▶");
            }
            @Override public void onPlayerError(PlaybackException error) {
                Toast.makeText(PlayerActivity.this, "Hata: " + error.getMessage(), Toast.LENGTH_SHORT).show();
            }
        });
    }

    private MediaSource buildSource(String url, DataSource.Factory dsf) {
        Uri uri = Uri.parse(url);
        String lo = url.toLowerCase();
        if (lo.contains(".mpd")  || lo.contains("dash"))   return new DashMediaSource.Factory(dsf).createMediaSource(MediaItem.fromUri(uri));
        if (lo.contains(".m3u8") || lo.contains("m3u8"))   return new HlsMediaSource.Factory(dsf).createMediaSource(MediaItem.fromUri(uri));
        if (lo.startsWith("rtsp://"))                       return new RtspMediaSource.Factory().createMediaSource(MediaItem.fromUri(uri));
        if (lo.contains(".ism")  || lo.contains("smooth"))  return new SsMediaSource.Factory(dsf).createMediaSource(MediaItem.fromUri(uri));
        if (lo.endsWith(".m3u"))                            return new HlsMediaSource.Factory(dsf).createMediaSource(MediaItem.fromUri(uri));
        return new ProgressiveMediaSource.Factory(dsf).createMediaSource(MediaItem.fromUri(uri));
    }

    private void cycleScale() {
        scaleModeIdx = (scaleModeIdx + 1) % SCALE_MODES.length;
        playerView.setResizeMode(SCALE_MODES[scaleModeIdx]);
        scaleTv.setText(SCALE_LABELS[scaleModeIdx]);
    }

    private void toggleCtrl() {
        if (locked) return;
        if (controlsVisible) hideAnim(); else showAnim();
    }
    private void showAnim() {
        controlsVisible = true;
        controlsOverlay.animate().alpha(1f).setDuration(200).start();
        scheduleHide();
    }
    private void hideAnim() {
        controlsVisible = false;
        controlsOverlay.animate().alpha(0f).setDuration(300).start();
    }
    private void scheduleHide() {
        handler.removeCallbacks(hideCtrl);
        handler.postDelayed(hideCtrl, 4000);
    }

    private TextView ctrlBtn(String label) {
        TextView tv = new TextView(this);
        tv.setText(label);
        tv.setTextSize(14); tv.setTextColor(Color.WHITE);
        tv.setPadding(dp(12), dp(6), dp(12), dp(6));
        tv.setGravity(Gravity.CENTER);
        return tv;
    }

    private String fmt(long ms) {
        long s = ms / 1000, m = s / 60;
        s = s % 60;
        long h = m / 60; m = m % 60;
        if (h > 0) return String.format("%d:%02d:%02d", h, m, s);
        return String.format("%d:%02d", m, s);
    }

    int dp(int v) { return Math.round(v * getResources().getDisplayMetrics().density); }

    @Override protected void onStop() { super.onStop(); if (player != null) player.pause(); }
    @Override protected void onDestroy() {
        super.onDestroy();
        handler.removeCallbacksAndMessages(null);
        if (player != null) { player.release(); player = null; }
    }
    @Override public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) getWindow().getDecorView().setSystemUiVisibility(
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY |
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION  |
            View.SYSTEM_UI_FLAG_FULLSCREEN);
    }
}
