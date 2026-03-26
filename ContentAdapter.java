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

    interface OnItemClick {
        void onClick(Map<String, Object> item);
    }

    static final int TYPE_HEADER = 0;
    static final int TYPE_ITEM   = 1;

    private final Context      ctx;
    private final String       display;
    private final String       primaryColor;
    private final OnItemClick  listener;
    private final List<Object> flatList = new ArrayList<>();

    public ContentAdapter(Context ctx, List<Map<String, Object>> items,
                          String display, String primaryColor, OnItemClick listener) {
        this.ctx          = ctx;
        this.display      = display;
        this.primaryColor = primaryColor;
        this.listener     = listener;
        buildFlat(items);
    }

    private void buildFlat(List<Map<String, Object>> items) {
        flatList.clear();
        Map<String, List<Map<String, Object>>> grouped = new LinkedHashMap<>();
        for (Map<String, Object> item : items) {
            Object gObj = item.get("group");
            String group = (gObj instanceof String) ? (String) gObj : "";
            if (!grouped.containsKey(group)) grouped.put(group, new ArrayList<>());
            grouped.get(group).add(item);
        }
        for (Map.Entry<String, List<Map<String, Object>>> e : grouped.entrySet()) {
            if (!e.getKey().isEmpty()) flatList.add(e.getKey());
            flatList.addAll(e.getValue());
        }
    }

    @Override public int getItemViewType(int pos) {
        return flatList.get(pos) instanceof String ? TYPE_HEADER : TYPE_ITEM;
    }

    @NonNull @Override
    public VH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        if (viewType == TYPE_HEADER) {
            TextView tv = new TextView(ctx);
            tv.setPadding(dp(16), dp(12), dp(16), dp(4));
            tv.setTextSize(11); tv.setTextColor(Color.parseColor("#9090b0"));
            tv.setAllCaps(true);
            tv.setLayoutParams(new RecyclerView.LayoutParams(-1, -2));
            return new VH(tv, null, null, null);
        }
        return "grid".equals(display) ? buildGridVH() : buildListVH();
    }

    @Override @SuppressWarnings("unchecked")
    public void onBindViewHolder(@NonNull VH vh, int pos) {
        Object obj = flatList.get(pos);
        if (obj instanceof String) {
            ((TextView) vh.root).setText((String) obj);
            return;
        }
        Map<String, Object> item = (Map<String, Object>) obj;
        String name  = str(item, "name");
        String logo  = str(item, "logo");
        String group = str(item, "group");

        if (vh.title    != null) vh.title.setText(name);
        if (vh.subtitle != null) vh.subtitle.setText(group);

        if (vh.logo != null) {
            vh.logo.setImageBitmap(null);
            if (vh.letter != null) vh.letter.setText(name.isEmpty() ? "?" : name.substring(0, 1).toUpperCase());
            if (!logo.isEmpty()) loadImage(logo, vh.logo);
        }
        vh.root.setOnClickListener(v -> listener.onClick(item));
    }

    @Override public int getItemCount() { return flatList.size(); }

    // ── ViewHolder builders ────────────────────────────────────
    private VH buildListVH() {
        LinearLayout row = new LinearLayout(ctx);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(12), dp(10), dp(12), dp(10));
        row.setBackgroundColor(Color.parseColor("#0f0f1a"));
        row.setLayoutParams(new RecyclerView.LayoutParams(-1, -2));

        FrameLayout logoFrame = makeLogoFrame(dp(52), dp(8));
        ImageView logo = new ImageView(ctx);
        logo.setLayoutParams(new FrameLayout.LayoutParams(-1, -1));
        logo.setScaleType(ImageView.ScaleType.CENTER_CROP);
        TextView letter = makeLetter(18);
        logoFrame.addView(logo); logoFrame.addView(letter);

        LinearLayout textCol = new LinearLayout(ctx);
        textCol.setOrientation(LinearLayout.VERTICAL);
        textCol.setPadding(dp(12), 0, 0, 0);
        textCol.setLayoutParams(new LinearLayout.LayoutParams(0, -2, 1f));

        TextView title = new TextView(ctx);
        title.setTextSize(14); title.setTextColor(Color.WHITE);
        title.setMaxLines(2);
        title.setEllipsize(android.text.TextUtils.TruncateAt.END);

        TextView sub = new TextView(ctx);
        sub.setTextSize(11); sub.setTextColor(Color.parseColor("#606080"));

        textCol.addView(title); textCol.addView(sub);

        TextView play = new TextView(ctx);
        play.setText("▶"); play.setTextSize(16);
        play.setTextColor(Color.parseColor("#6c63ff"));
        play.setPadding(dp(8), 0, 0, 0);

        row.addView(logoFrame); row.addView(textCol); row.addView(play);
        return new VH(row, logo, letter, title, sub);
    }

    private VH buildGridVH() {
        LinearLayout col = new LinearLayout(ctx);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setGravity(Gravity.CENTER);
        col.setPadding(dp(6), dp(8), dp(6), dp(8));
        col.setBackgroundColor(Color.parseColor("#0f0f1a"));
        col.setLayoutParams(new RecyclerView.LayoutParams(-1, -2));

        FrameLayout logoFrame = makeLogoFrame(dp(70), dp(12));
        ImageView logo = new ImageView(ctx);
        logo.setLayoutParams(new FrameLayout.LayoutParams(-1, -1));
        logo.setScaleType(ImageView.ScaleType.CENTER_CROP);
        logo.setPadding(dp(4), dp(4), dp(4), dp(4));
        TextView letter = makeLetter(22);
        logoFrame.addView(logo); logoFrame.addView(letter);

        TextView title = new TextView(ctx);
        title.setTextSize(10); title.setTextColor(Color.WHITE);
        title.setGravity(Gravity.CENTER);
        title.setMaxLines(2);
        title.setEllipsize(android.text.TextUtils.TruncateAt.END);
        title.setPadding(dp(2), dp(5), dp(2), 0);

        col.addView(logoFrame); col.addView(title);
        return new VH(col, logo, letter, title, null);
    }

    // ── Image loading ──────────────────────────────────────────
    private void loadImage(String urlStr, ImageView target) {
        new Thread(new Runnable() {
            @Override public void run() {
                try {
                    HttpURLConnection conn = (HttpURLConnection) new URL(urlStr).openConnection();
                    conn.setConnectTimeout(5000); conn.setReadTimeout(8000);
                    conn.setRequestProperty("User-Agent","Mozilla/5.0");
                    InputStream is = conn.getInputStream();
                    final Bitmap bmp = BitmapFactory.decodeStream(is);
                    if (bmp != null) {
                        new Handler(Looper.getMainLooper()).post(new Runnable() {
                            @Override public void run() {
                                if (target != null) target.setImageBitmap(bmp);
                            }
                        });
                    }
                } catch (Exception ignored) {}
            }
        }).start();
    }

    // ── Helpers ────────────────────────────────────────────────
    private FrameLayout makeLogoFrame(int size, int cornerRadius) {
        FrameLayout f = new FrameLayout(ctx);
        f.setLayoutParams(new LinearLayout.LayoutParams(size, size));
        GradientDrawable bg = new GradientDrawable();
        bg.setShape(GradientDrawable.RECTANGLE);
        bg.setCornerRadius(cornerRadius);
        bg.setColor(Color.parseColor("#1a1a2e"));
        bg.setStroke(dp(1), Color.parseColor("#2a2a42"));
        f.setBackground(bg);
        return f;
    }

    private TextView makeLetter(int textSizeSp) {
        TextView tv = new TextView(ctx);
        tv.setLayoutParams(new FrameLayout.LayoutParams(-1, -1));
        tv.setGravity(Gravity.CENTER);
        tv.setTextSize(textSizeSp); tv.setTextColor(Color.parseColor("#6c63ff"));
        tv.setTypeface(null, android.graphics.Typeface.BOLD);
        return tv;
    }

    static String str(Map<String, Object> m, String k) {
        Object v = m.get(k);
        return (v instanceof String) ? (String) v : "";
    }

    int dp(int v) { return Math.round(v * ctx.getResources().getDisplayMetrics().density); }

    // ── ViewHolder ────────────────────────────────────────────
    static class VH extends RecyclerView.ViewHolder {
        View      root;
        ImageView logo;
        TextView  letter, title, subtitle;

        VH(View root, ImageView logo, TextView letter, TextView title) {
            super(root);
            this.root = root; this.logo = logo; this.letter = letter; this.title = title;
        }
        VH(View root, ImageView logo, TextView letter, TextView title, TextView subtitle) {
            super(root);
            this.root = root; this.logo = logo; this.letter = letter;
            this.title = title; this.subtitle = subtitle;
        }
    }
}
