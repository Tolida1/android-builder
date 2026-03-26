package PACKAGE_PLACEHOLDER;

import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.view.*;
import android.widget.*;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;
import java.util.*;

public class ContentAdapter extends RecyclerView.Adapter<ContentAdapter.VH> {

    interface OnItemClick { void onClick(Map<String,Object> item); }

    private final Context              ctx;
    private final List<Map<String,Object>> items;
    private final String               display;
    private final String               primaryColor;
    private final OnItemClick          listener;

    // Grouped data
    private final List<Object> flatList = new ArrayList<>(); // String=header, Map=item

    public ContentAdapter(Context ctx, List<Map<String,Object>> items,
                          String display, String primaryColor, OnItemClick listener) {
        this.ctx          = ctx;
        this.items        = items;
        this.display      = display;
        this.primaryColor = primaryColor;
        this.listener     = listener;
        buildFlatList();
    }

    private void buildFlatList() {
        flatList.clear();
        // Group by "group" field
        Map<String, List<Map<String,Object>>> grouped = new LinkedHashMap<>();
        for (Map<String,Object> item : items) {
            String group = (String) item.getOrDefault("group","");
            if (!grouped.containsKey(group)) grouped.put(group, new ArrayList<>());
            grouped.get(group).add(item);
        }
        for (Map.Entry<String,List<Map<String,Object>>> e : grouped.entrySet()) {
            if (!e.getKey().isEmpty()) flatList.add(e.getKey()); // header
            flatList.addAll(e.getValue());
        }
    }

    static final int TYPE_HEADER = 0;
    static final int TYPE_ITEM   = 1;

    @Override public int getItemViewType(int pos) {
        return flatList.get(pos) instanceof String ? TYPE_HEADER : TYPE_ITEM;
    }

    @NonNull @Override
    public VH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        if (viewType == TYPE_HEADER) {
            TextView tv = new TextView(ctx);
            tv.setPadding(dp(16),dp(12),dp(16),dp(4));
            tv.setTextSize(12);
            tv.setTextColor(Color.parseColor("#9090b0"));
            tv.setAllCaps(true);
            tv.setLetterSpacing(0.08f);
            tv.setLayoutParams(new RecyclerView.LayoutParams(-1,-2));
            return new VH(tv);
        }
        if ("grid".equals(display)) {
            return new VH(buildGridItem());
        }
        return new VH(buildListItem());
    }

    @SuppressWarnings("unchecked")
    @Override public void onBindViewHolder(@NonNull VH vh, int pos) {
        Object obj = flatList.get(pos);
        if (obj instanceof String) {
            ((TextView)vh.itemView).setText((String)obj);
            return;
        }
        Map<String,Object> item = (Map<String,Object>) obj;
        String name   = (String) item.getOrDefault("name","");
        String logo   = (String) item.getOrDefault("logo","");
        String group  = (String) item.getOrDefault("group","");

        if ("grid".equals(display)) {
            bindGrid(vh, name, logo);
        } else {
            bindList(vh, name, logo, group);
        }
        vh.itemView.setOnClickListener(v -> listener.onClick(item));
    }

    private void bindList(VH vh, String name, String logo, String group) {
        if (vh.title != null) vh.title.setText(name);
        if (vh.subtitle != null) vh.subtitle.setText(group);
        if (vh.logo != null) {
            if (logo != null && !logo.isEmpty()) {
                // Load logo with simple AsyncTask
                new Thread(() -> {
                    try {
                        java.net.URL url = new java.net.URL(logo);
                        android.graphics.Bitmap bmp = android.graphics.BitmapFactory.decodeStream(url.openStream());
                        if(bmp!=null && vh.logo!=null)
                            ((Activity)ctx).runOnUiThread(()-> vh.logo.setImageBitmap(bmp));
                    } catch(Exception ignored){}
                }).start();
            } else {
                vh.logo.setBackgroundColor(Color.parseColor("#1a1a2e"));
                // First letter
                if (vh.logoLetter != null) vh.logoLetter.setText(name.isEmpty()?"?":(name.substring(0,1).toUpperCase()));
            }
        }
    }

    private void bindGrid(VH vh, String name, String logo) {
        if (vh.title != null) vh.title.setText(name);
        if (vh.logo != null && logo != null && !logo.isEmpty()) {
            new Thread(() -> {
                try {
                    java.net.URL url = new java.net.URL(logo);
                    android.graphics.Bitmap bmp = android.graphics.BitmapFactory.decodeStream(url.openStream());
                    if(bmp!=null && vh.logo!=null)
                        ((Activity)ctx).runOnUiThread(()-> vh.logo.setImageBitmap(bmp));
                } catch(Exception ignored){}
            }).start();
        } else if (vh.logoLetter != null) {
            vh.logoLetter.setText(name.isEmpty()?"?":(name.substring(0,1).toUpperCase()));
        }
    }

    @Override public int getItemCount() { return flatList.size(); }

    // ── Build item views ─────────────────────────────────────
    private View buildListItem() {
        LinearLayout row = new LinearLayout(ctx);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(12),dp(10),dp(12),dp(10));
        row.setBackgroundColor(Color.parseColor("#0f0f1a"));

        // Logo container
        FrameLayout logoFrame = new FrameLayout(ctx);
        int sz = dp(52);
        logoFrame.setLayoutParams(new LinearLayout.LayoutParams(sz,sz));
        logoFrame.setPadding(dp(2),dp(2),dp(2),dp(2));
        GradientDrawable border = new GradientDrawable();
        border.setShape(GradientDrawable.RECTANGLE);
        border.setCornerRadius(dp(8));
        border.setColor(Color.parseColor("#1a1a2e"));
        border.setStroke(dp(1),Color.parseColor("#2a2a42"));
        logoFrame.setBackground(border);

        ImageView logo = new ImageView(ctx);
        logo.setLayoutParams(new FrameLayout.LayoutParams(-1,-1));
        logo.setScaleType(ImageView.ScaleType.CENTER_CROP);

        TextView letter = new TextView(ctx);
        letter.setLayoutParams(new FrameLayout.LayoutParams(-1,-1));
        letter.setGravity(Gravity.CENTER);
        letter.setTextSize(18); letter.setTextColor(Color.parseColor("#6c63ff"));
        letter.setTypeface(null, android.graphics.Typeface.BOLD);

        logoFrame.addView(logo); logoFrame.addView(letter);

        // Text
        LinearLayout textCol = new LinearLayout(ctx);
        textCol.setOrientation(LinearLayout.VERTICAL);
        textCol.setPadding(dp(12),0,0,0);
        LinearLayout.LayoutParams tcp = new LinearLayout.LayoutParams(0,-2,1f);
        textCol.setLayoutParams(tcp);

        TextView title = new TextView(ctx);
        title.setTextSize(14); title.setTextColor(Color.WHITE);
        title.setMaxLines(2); title.setEllipsize(android.text.TextUtils.TruncateAt.END);

        TextView subtitle = new TextView(ctx);
        subtitle.setTextSize(11); subtitle.setTextColor(Color.parseColor("#6060808"));
        subtitle.setMaxLines(1);

        textCol.addView(title); textCol.addView(subtitle);
        row.addView(logoFrame); row.addView(textCol);

        // Play icon
        TextView play = new TextView(ctx);
        play.setText("▶");
        play.setTextSize(16); play.setTextColor(Color.parseColor("#6c63ff"));
        play.setPadding(dp(8),0,0,0);
        row.addView(play);

        // Add divider (using margin)
        row.setTag("listitem");

        VH.ListItemHolder holder = new VH.ListItemHolder();
        holder.logo=logo; holder.logoLetter=letter; holder.title=title; holder.subtitle=subtitle;
        row.setTag(holder);

        return row;
    }

    private View buildGridItem() {
        LinearLayout col = new LinearLayout(ctx);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setGravity(Gravity.CENTER);
        col.setPadding(dp(6),dp(8),dp(6),dp(8));
        col.setBackgroundColor(Color.parseColor("#0f0f1a"));

        FrameLayout logoFrame = new FrameLayout(ctx);
        int sz = dp(70);
        logoFrame.setLayoutParams(new LinearLayout.LayoutParams(sz,sz));
        GradientDrawable bg = new GradientDrawable();
        bg.setShape(GradientDrawable.RECTANGLE);
        bg.setCornerRadius(dp(12));
        bg.setColor(Color.parseColor("#1a1a2e"));
        bg.setStroke(dp(1),Color.parseColor("#2a2a42"));
        logoFrame.setBackground(bg);

        ImageView logo = new ImageView(ctx);
        logo.setLayoutParams(new FrameLayout.LayoutParams(-1,-1));
        logo.setScaleType(ImageView.ScaleType.CENTER_CROP);
        logo.setPadding(dp(4),dp(4),dp(4),dp(4));

        TextView letter = new TextView(ctx);
        letter.setLayoutParams(new FrameLayout.LayoutParams(-1,-1));
        letter.setGravity(Gravity.CENTER);
        letter.setTextSize(22); letter.setTextColor(Color.parseColor("#6c63ff"));
        letter.setTypeface(null, android.graphics.Typeface.BOLD);

        logoFrame.addView(logo); logoFrame.addView(letter);

        TextView title = new TextView(ctx);
        title.setTextSize(10); title.setTextColor(Color.WHITE);
        title.setGravity(Gravity.CENTER);
        title.setMaxLines(2); title.setEllipsize(android.text.TextUtils.TruncateAt.END);
        title.setPadding(dp(2),dp(5),dp(2),0);

        col.addView(logoFrame); col.addView(title);

        VH.ListItemHolder holder = new VH.ListItemHolder();
        holder.logo=logo; holder.logoLetter=letter; holder.title=title;
        col.setTag(holder);

        return col;
    }

    static class VH extends RecyclerView.ViewHolder {
        ImageView logo;
        TextView  title, subtitle, logoLetter;

        static class ListItemHolder {
            ImageView logo; TextView title, subtitle, logoLetter;
        }

        VH(View v) {
            super(v);
            if (v.getTag() instanceof ListItemHolder) {
                ListItemHolder h = (ListItemHolder) v.getTag();
                logo=h.logo; title=h.title; subtitle=h.subtitle; logoLetter=h.logoLetter;
            }
        }
    }

    int dp(int v) { return Math.round(v * ctx.getResources().getDisplayMetrics().density); }
}
