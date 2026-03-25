// ============================================================
// AppFirebaseMessagingService.java
// FCM bildirimi gelince çalışır
// Bildirime tıklanınca URL açar
// ============================================================
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

    private static final String CHANNEL_ID   = "app_notifications";
    private static final String CHANNEL_NAME = "Bildirimler";
    private static final int    NOTIF_ID     = 1001;

    @Override
    public void onMessageReceived(RemoteMessage message) {
        super.onMessageReceived(message);

        Map<String, String> data = message.getData();

        String title    = data.getOrDefault("title",    "Bildirim");
        String body     = data.getOrDefault("body",     "");
        String imageUrl = data.getOrDefault("imageUrl", "");
        String clickUrl = data.getOrDefault("clickUrl", "");

        // Bildirim kanalı oluştur (Android 8+)
        createNotificationChannel();

        // Tıklanınca URL aç
        Intent intent;
        if (!clickUrl.isEmpty()) {
            intent = new Intent(Intent.ACTION_VIEW, Uri.parse(clickUrl));
        } else {
            intent = new Intent(this, MainActivity.class);
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
        }

        PendingIntent pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_ONE_SHOT | PendingIntent.FLAG_IMMUTABLE
        );

        NotificationCompat.Builder builder = new NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent);

        // Büyük metin
        builder.setStyle(new NotificationCompat.BigTextStyle().bigText(body));

        // Görsel varsa indir ve ekle
        if (!imageUrl.isEmpty()) {
            Bitmap bitmap = downloadBitmap(imageUrl);
            if (bitmap != null) {
                builder.setStyle(
                    new NotificationCompat.BigPictureStyle()
                        .bigPicture(bitmap)
                        .setSummaryText(body)
                );
                builder.setLargeIcon(bitmap);
            }
        }

        NotificationManager manager =
            (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        manager.notify(NOTIF_ID, builder.build());
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            );
            channel.setDescription("Uygulama bildirimleri");
            NotificationManager manager = getSystemService(NotificationManager.class);
            manager.createNotificationChannel(channel);
        }
    }

    private Bitmap downloadBitmap(String urlStr) {
        try {
            URL url = new URL(urlStr);
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setDoInput(true);
            conn.setConnectTimeout(5000);
            conn.setReadTimeout(5000);
            conn.connect();
            InputStream is = conn.getInputStream();
            return BitmapFactory.decodeStream(is);
        } catch (Exception e) {
            return null;
        }
    }
}
