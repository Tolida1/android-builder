#!/bin/bash
# ============================================================
# build_app.sh — Firebase Entegreli Android Builder (v2 - Fixed)
# ============================================================
set -e

echo "=========================================="
echo "  BUILD: $APP_NAME ($PACKAGE_NAME)"
echo "  Owner: $OWNER_ID | App: $APP_ID"
echo "=========================================="

# ── ORTAM KONTROLÜ ───────────────────────────────────────────
echo "Java version:"
java -version 2>&1 | head -1

echo "Gradle version:"
gradle --version 2>&1 | grep "Gradle" | head -1

# Android SDK yolları
ANDROID_SDK="${ANDROID_HOME:-/usr/local/lib/android/sdk}"
BUILD_TOOLS_DIR=$(ls -d "$ANDROID_SDK/build-tools/"* 2>/dev/null | sort -V | tail -1)

if [ -z "$BUILD_TOOLS_DIR" ]; then
    echo "HATA: Build tools bulunamadı!"
    exit 1
fi

export PATH="$BUILD_TOOLS_DIR:$ANDROID_SDK/platform-tools:$PATH"
echo "Build tools: $BUILD_TOOLS_DIR"

# ── BUILD DİZİNİ ─────────────────────────────────────────────
BUILD_DIR="/tmp/build_${APP_ID}_$$"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

PACKAGE_PATH=$(echo "$PACKAGE_NAME" | tr '.' '/')
mkdir -p app/src/main/java/$PACKAGE_PATH
mkdir -p app/src/main/res/{values,mipmap-hdpi,mipmap-mdpi,mipmap-xhdpi,mipmap-xxhdpi,mipmap-xxxhdpi}

# ── JAVA DOSYALARI ───────────────────────────────────────────
cat > app/src/main/java/$PACKAGE_PATH/MainActivity.java << JAVA_EOF
package ${PACKAGE_NAME};

import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebSettings;
import android.webkit.WebChromeClient;
import android.view.Window;
import android.view.WindowManager;
import android.Manifest;
import android.content.pm.PackageManager;
import android.os.Build;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import com.google.firebase.firestore.FirebaseFirestore;
import com.google.firebase.firestore.SetOptions;
import com.google.firebase.messaging.FirebaseMessaging;
import java.util.HashMap;
import java.util.Map;

public class MainActivity extends Activity {
    private WebView webView;
    private static final int NOTIFICATION_PERMISSION_CODE = 1001;
    private static final String OWNER_ID = "${OWNER_ID}";
    private static final String APP_ID = "${APP_ID}";
    private static final String CONTENT_URL = "${CONTENT_URL:-https://example.com}";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(
            WindowManager.LayoutParams.FLAG_FULLSCREEN,
            WindowManager.LayoutParams.FLAG_FULLSCREEN
        );

        webView = new WebView(this);
        setContentView(webView);

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(true);
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(true);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);

        webView.setWebViewClient(new WebViewClient());
        webView.setWebChromeClient(new WebChromeClient());
        webView.loadUrl(CONTENT_URL);

        requestNotificationPermission();
        initializeFirebase();
    }

    private void requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                    != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this,
                    new String[]{Manifest.permission.POST_NOTIFICATIONS},
                    NOTIFICATION_PERMISSION_CODE);
            }
        }
    }

    private void initializeFirebase() {
        FirebaseMessaging.getInstance().subscribeToTopic("app_" + APP_ID)
            .addOnCompleteListener(task -> {
                if (task.isSuccessful()) {
                    System.out.println("Topic subscription successful");
                }
            });

        FirebaseMessaging.getInstance().getToken()
            .addOnCompleteListener(task -> {
                if (task.isSuccessful() && task.getResult() != null) {
                    String token = task.getResult();
                    saveTokenToFirestore(token);
                }
            });
    }

    private void saveTokenToFirestore(String token) {
        FirebaseFirestore db = FirebaseFirestore.getInstance();
        
        Map<String, Object> deviceData = new HashMap<>();
        deviceData.put("token", token);
        deviceData.put("platform", "android");
        deviceData.put("appId", APP_ID);
        deviceData.put("ownerId", OWNER_ID);
        deviceData.put("lastUpdated", System.currentTimeMillis());
        deviceData.put("deviceModel", Build.MODEL);
        deviceData.put("sdkVersion", Build.VERSION.SDK_INT);

        String deviceId = token.substring(0, Math.min(token.length(), 20));
        
        db.collection("owners")
            .document(OWNER_ID)
            .collection("apps")
            .document(APP_ID)
            .collection("devices")
            .document(deviceId)
            .set(deviceData, SetOptions.merge())
            .addOnSuccessListener(aVoid -> 
                System.out.println("Device registered successfully"))
            .addOnFailureListener(e -> 
                System.err.println("Device registration failed: " + e.getMessage()));
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.destroy();
        }
        super.onDestroy();
    }
}
JAVA_EOF

cat > app/src/main/java/$PACKAGE_PATH/AppFirebaseMessagingService.java << JAVA_EOF
package ${PACKAGE_NAME};

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Intent;
import android.content.Context;
import android.os.Build;
import android.media.RingtoneManager;
import android.net.Uri;
import androidx.core.app.NotificationCompat;
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;
import com.google.firebase.firestore.FirebaseFirestore;
import com.google.firebase.firestore.SetOptions;
import java.util.HashMap;
import java.util.Map;

public class AppFirebaseMessagingService extends FirebaseMessagingService {
    private static final String CHANNEL_ID = "app_notifications";
    private static final String OWNER_ID = "${OWNER_ID}";
    private static final String APP_ID = "${APP_ID}";

    @Override
    public void onNewToken(String token) {
        super.onNewToken(token);
        sendTokenToServer(token);
    }

    private void sendTokenToServer(String token) {
        FirebaseFirestore db = FirebaseFirestore.getInstance();
        
        Map<String, Object> deviceData = new HashMap<>();
        deviceData.put("token", token);
        deviceData.put("platform", "android");
        deviceData.put("appId", APP_ID);
        deviceData.put("ownerId", OWNER_ID);
        deviceData.put("lastUpdated", System.currentTimeMillis());
        deviceData.put("deviceModel", Build.MODEL);
        deviceData.put("sdkVersion", Build.VERSION.SDK_INT);

        String deviceId = token.substring(0, Math.min(token.length(), 20));
        
        db.collection("owners")
            .document(OWNER_ID)
            .collection("apps")
            .document(APP_ID)
            .collection("devices")
            .document(deviceId)
            .set(deviceData, SetOptions.merge());
    }

    @Override
    public void onMessageReceived(RemoteMessage remoteMessage) {
        super.onMessageReceived(remoteMessage);
        
        String title = "Bildirim";
        String body = "";
        
        if (remoteMessage.getNotification() != null) {
            title = remoteMessage.getNotification().getTitle() != null 
                ? remoteMessage.getNotification().getTitle() : title;
            body = remoteMessage.getNotification().getBody() != null 
                ? remoteMessage.getNotification().getBody() : body;
        }
        
        if (remoteMessage.getData().size() > 0) {
            if (remoteMessage.getData().containsKey("title")) {
                title = remoteMessage.getData().get("title");
            }
            if (remoteMessage.getData().containsKey("body")) {
                body = remoteMessage.getData().get("body");
            }
        }
        
        sendNotification(title, body);
    }

    private void sendNotification(String title, String messageBody) {
        Intent intent = new Intent(this, MainActivity.class);
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
        
        int flags = PendingIntent.FLAG_ONE_SHOT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags |= PendingIntent.FLAG_IMMUTABLE;
        }
        
        PendingIntent pendingIntent = PendingIntent.getActivity(
            this, 0, intent, flags);

        Uri defaultSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
        
        NotificationCompat.Builder notificationBuilder =
            new NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title)
                .setContentText(messageBody)
                .setAutoCancel(true)
                .setSound(defaultSoundUri)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(pendingIntent);

        NotificationManager notificationManager =
            (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "Uygulama Bildirimleri",
                NotificationManager.IMPORTANCE_HIGH);
            channel.setDescription("Uygulama bildirimleri için kanal");
            notificationManager.createNotificationChannel(channel);
        }

        int notificationId = (int) System.currentTimeMillis();
        notificationManager.notify(notificationId, notificationBuilder.build());
    }
}
JAVA_EOF

# ── ANDROIDMANIFEST ──────────────────────────────────────────
cat > app/src/main/AndroidManifest.xml << MANIFEST_EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="${PACKAGE_NAME}">
    
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    
    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:usesCleartextTraffic="true"
        android:theme="@style/AppTheme">
        
        <activity 
            android:name=".MainActivity" 
            android:exported="true"
            android:launchMode="singleTop"
            android:configChanges="orientation|screenSize|keyboardHidden">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        
        <service 
            android:name=".AppFirebaseMessagingService" 
            android:exported="false">
            <intent-filter>
                <action android:name="com.google.firebase.MESSAGING_EVENT" />
            </intent-filter>
        </service>
        
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="app_notifications" />
            
    </application>
</manifest>
MANIFEST_EOF

# ── RENKLER & STİLLER ────────────────────────────────────────
cat > app/src/main/res/values/colors.xml << EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="primaryColor">${PRIMARY_COLOR:-#2196F3}</color>
    <color name="primaryDarkColor">${PRIMARY_DARK_COLOR:-#1565C0}</color>
    <color name="accentColor">${ACCENT_COLOR:-#FF4081}</color>
    <color name="white">#FFFFFF</color>
    <color name="black">#000000</color>
</resources>
EOF

cat > app/src/main/res/values/strings.xml << EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">${APP_NAME}</string>
    <string name="default_notification_channel_id">app_notifications</string>
</resources>
EOF

cat > app/src/main/res/values/styles.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="AppTheme" parent="android:Theme.Material.Light.NoActionBar">
        <item name="android:colorPrimary">@color/primaryColor</item>
        <item name="android:colorPrimaryDark">@color/primaryDarkColor</item>
        <item name="android:colorAccent">@color/accentColor</item>
        <item name="android:statusBarColor">@color/primaryDarkColor</item>
        <item name="android:windowBackground">@color/white</item>
    </style>
</resources>
EOF

# ── İKON ─────────────────────────────────────────────────────
echo "İkonlar oluşturuluyor..."

# ImageMagick kurulumu (hata durumunda devam et)
if ! command -v convert &> /dev/null; then
    echo "ImageMagick kuruluyor..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq imagemagick 2>/dev/null || true
fi

generate_icon() {
    local size=$1 
    local dpi=$2
    local output_dir="app/src/main/res/mipmap-$dpi"
    
    mkdir -p "$output_dir"
    
    if [ -f /tmp/icon_source.png ]; then
        convert /tmp/icon_source.png -resize ${size}x${size} \
            "$output_dir/ic_launcher.png" 2>/dev/null || create_default_icon "$size" "$output_dir"
    else
        create_default_icon "$size" "$output_dir"
    fi
    
    cp "$output_dir/ic_launcher.png" "$output_dir/ic_launcher_round.png" 2>/dev/null || true
}

create_default_icon() {
    local size=$1
    local output_dir=$2
    local letter="${APP_NAME:0:1}"
    local color="${PRIMARY_COLOR:-#2196F3}"
    
    if command -v convert &> /dev/null; then
        convert -size ${size}x${size} xc:"$color" \
            -fill white -gravity center \
            -pointsize $((size/3)) -annotate 0 "$letter" \
            "$output_dir/ic_launcher.png" 2>/dev/null || create_simple_icon "$size" "$output_dir" "$color"
    else
        create_simple_icon "$size" "$output_dir" "$color"
    fi
}

create_simple_icon() {
    local size=$1
    local output_dir=$2
    local color=$3
    
    # Basit bir PNG oluştur (1x1 piksel, sonra boyutlandır)
    # PPM formatında basit ikon
    local r=$((16#${color:1:2}))
    local g=$((16#${color:3:2}))
    local b=$((16#${color:5:2}))
    
    echo "P6 $size $size 255" > /tmp/temp_icon.ppm
    for ((i=0; i<size*size; i++)); do
        printf "\\x$(printf '%02x' $r)\\x$(printf '%02x' $g)\\x$(printf '%02x' $b)"
    done >> /tmp/temp_icon.ppm
    
    if command -v convert &> /dev/null; then
        convert /tmp/temp_icon.ppm "$output_dir/ic_launcher.png" 2>/dev/null
    fi
    rm -f /tmp/temp_icon.ppm
}

# İkon URL'si varsa indir
if [ -n "$ICON_URL" ] && [ "$ICON_URL" != "null" ]; then
    echo "İkon indiriliyor: $ICON_URL"
    wget -q "$ICON_URL" -O /tmp/icon_source.png 2>/dev/null || \
    curl -sL "$ICON_URL" -o /tmp/icon_source.png 2>/dev/null || \
    echo "İkon indirilemedi, varsayılan kullanılacak"
fi

generate_icon 48  mdpi
generate_icon 72  hdpi
generate_icon 96  xhdpi
generate_icon 144 xxhdpi
generate_icon 192 xxxhdpi

echo "İkonlar oluşturuldu."

# ── GOOGLE-SERVICES.JSON KONTROLÜ ────────────────────────────
echo "Google Services JSON kontrol ediliyor..."

if [ -z "$GOOGLE_SERVICES_JSON" ] || [ "$GOOGLE_SERVICES_JSON" == "null" ]; then
    echo "HATA: GOOGLE_SERVICES_JSON tanımlanmamış!"
    exit 1
fi

# JSON'u dosyaya yaz ve doğrula
echo "$GOOGLE_SERVICES_JSON" > app/google-services.json

# JSON formatını kontrol et
if ! python3 -c "import json; json.load(open('app/google-services.json'))" 2>/dev/null; then
    if ! jq empty app/google-services.json 2>/dev/null; then
        echo "UYARI: google-services.json formatı doğrulanamadı"
    fi
fi

echo "Google Services JSON kaydedildi."

# ── GRADLE WRAPPER ───────────────────────────────────────────
mkdir -p gradle/wrapper

cat > gradle/wrapper/gradle-wrapper.properties << 'EOF'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.5-bin.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

# ── ROOT BUILD.GRADLE ────────────────────────────────────────
cat > build.gradle << 'EOF'
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:8.2.2'
        classpath 'com.google.gms:google-services:4.4.1'
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

task clean(type: Delete) {
    delete rootProject.buildDir
}
EOF

# ── SETTINGS.GRADLE ──────────────────────────────────────────
cat > settings.gradle << 'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "app"
include ':app'
EOF

# ── APP BUILD.GRADLE ─────────────────────────────────────────
cat > app/build.gradle << EOF
plugins {
    id 'com.android.application'
    id 'com.google.gms.google-services'
}

android {
    namespace "${PACKAGE_NAME}"
    compileSdk 34

    defaultConfig {
        applicationId "${PACKAGE_NAME}"
        minSdk 24
        targetSdk 34
        versionCode ${VERSION_CODE:-1}
        versionName "${VERSION_NAME:-1.0}"
        
        multiDexEnabled true
    }

    buildTypes {
        release {
            minifyEnabled false
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
        debug {
            minifyEnabled false
        }
    }
    
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
    
    packagingOptions {
        resources {
            excludes += '/META-INF/{AL2.0,LGPL2.1}'
            excludes += 'META-INF/NOTICE.md'
            excludes += 'META-INF/LICENSE.md'
        }
    }
    
    lint {
        abortOnError false
        checkReleaseBuilds false
    }
}

dependencies {
    // Firebase BOM - tüm Firebase sürümlerini yönetir
    implementation platform('com.google.firebase:firebase-bom:32.7.4')
    
    // Firebase kütüphaneleri (BOM sayesinde sürüm belirtmeye gerek yok)
    implementation 'com.google.firebase:firebase-firestore'
    implementation 'com.google.firebase:firebase-messaging'
    
    // AndroidX
    implementation 'androidx.core:core:1.12.0'
    implementation 'androidx.appcompat:appcompat:1.6.1'
    
    // MultiDex (minSdk < 21 için gerekli ama yine de ekleyelim)
    implementation 'androidx.multidex:multidex:2.0.1'
}
EOF

# ── PROGUARD RULES ───────────────────────────────────────────
cat > app/proguard-rules.pro << 'EOF'
# Firebase
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# WebView
-keepclassmembers class * extends android.webkit.WebViewClient {
    public void *(android.webkit.WebView, java.lang.String, android.graphics.Bitmap);
    public boolean *(android.webkit.WebView, java.lang.String);
    public void *(android.webkit.WebView, java.lang.String);
}
EOF

# ── LOCAL.PROPERTIES ─────────────────────────────────────────
cat > local.properties << EOF
sdk.dir=${ANDROID_SDK}
EOF

# ── GRADLE BUILD ─────────────────────────────────────────────
echo ""
echo "=========================================="
echo "  GRADLE BUILD BAŞLIYOR"
echo "=========================================="
echo ""

# Gradle cache temizle (opsiyonel, sorun varsa aktifleştir)
# rm -rf ~/.gradle/caches/

# Gradle daemon'ı kapat (CI ortamı için önerilir)
export GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.parallel=true -Dorg.gradle.caching=true -Xmx4096m"

# Build işlemi - detaylı log ile
echo "Dependency'ler çözümleniyor..."
gradle dependencies --configuration releaseRuntimeClasspath 2>&1 | tail -30 || true

echo ""
echo "APK ve AAB oluşturuluyor..."

# --stacktrace ile hata detaylarını göster
if ! gradle assembleRelease bundleRelease --stacktrace --warning-mode all 2>&1 | tee /tmp/gradle_build.log; then
    echo ""
    echo "=========================================="
    echo "  BUILD HATASI!"
    echo "=========================================="
    echo ""
    echo "Son 50 satır log:"
    tail -50 /tmp/gradle_build.log
    echo ""
    
    # Hata analizi
    if grep -q "Could not resolve" /tmp/gradle_build.log; then
        echo "SORUN: Dependency çözümlenemedi. İnternet bağlantısını kontrol edin."
    fi
    if grep -q "Execution failed for task" /tmp/gradle_build.log; then
        echo "SORUN: Bir task başarısız oldu."
        grep "Execution failed for task" /tmp/gradle_build.log
    fi
    if grep -q "compileSdk" /tmp/gradle_build.log; then
        echo "SORUN: SDK sürüm uyumsuzluğu olabilir."
    fi
    
    exit 1
fi

echo ""
echo "Build başarılı!"
echo ""

# ── ÇIKTI DOSYALARINI KONTROL ET ─────────────────────────────
APK_UNSIGNED="$BUILD_DIR/app/build/outputs/apk/release/app-release-unsigned.apk"
AAB_FILE="$BUILD_DIR/app/build/outputs/bundle/release/app-release.aab"

echo "Çıktı dosyaları kontrol ediliyor..."
ls -la "$BUILD_DIR/app/build/outputs/apk/release/" 2>/dev/null || echo "APK dizini bulunamadı"
ls -la "$BUILD_DIR/app/build/outputs/bundle/release/" 2>/dev/null || echo "AAB dizini bulunamadı"

if [ ! -f "$APK_UNSIGNED" ]; then
    echo "HATA: APK dosyası oluşturulamadı!"
    echo "Beklenen konum: $APK_UNSIGNED"
    
    # Alternatif konumları kontrol et
    find "$BUILD_DIR" -name "*.apk" 2>/dev/null || echo "Hiç APK bulunamadı"
    exit 1
fi

echo "APK bulundu: $APK_UNSIGNED"

# ── KEYSTORE OLUŞTUR ─────────────────────────────────────────
echo "Keystore oluşturuluyor..."

KEYSTORE_FILE="/tmp/release-keystore.jks"
KEYSTORE_PASS="android123"
KEY_ALIAS="release-key"

keytool -genkeypair -v \
    -keystore "$KEYSTORE_FILE" \
    -alias "$KEY_ALIAS" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -storepass "$KEYSTORE_PASS" \
    -keypass "$KEYSTORE_PASS" \
    -dname "CN=App Builder, OU=Mobile, O=Company, L=Istanbul, ST=Istanbul, C=TR" \
    -noprompt 2>/dev/null

echo "Keystore oluşturuldu."

# ── APK İMZALA ───────────────────────────────────────────────
echo "APK imzalanıyor..."

APK_ALIGNED="/tmp/app-release-aligned.apk"
APK_SIGNED="/tmp/${PACKAGE_NAME}_v${VERSION_CODE:-1}.apk"

# Zipalign
"$BUILD_TOOLS_DIR/zipalign" -v -p 4 "$APK_UNSIGNED" "$APK_ALIGNED"

# Sign
"$BUILD_TOOLS_DIR/apksigner" sign \
    --ks "$KEYSTORE_FILE" \
    --ks-key-alias "$KEY_ALIAS" \
    --ks-pass "pass:$KEYSTORE_PASS" \
    --key-pass "pass:$KEYSTORE_PASS" \
    --out "$APK_SIGNED" \
    "$APK_ALIGNED"

# Verify
"$BUILD_TOOLS_DIR/apksigner" verify --verbose "$APK_SIGNED"

echo "APK imzalandı: $APK_SIGNED"

# ── AAB KOPYALA ──────────────────────────────────────────────
AAB_OUT="/tmp/${PACKAGE_NAME}_v${VERSION_CODE:-1}.aab"

if [ -f "$AAB_FILE" ]; then
    cp "$AAB_FILE" "$AAB_OUT"
    echo "AAB kopyalandı: $AAB_OUT"
else
    echo "UYARI: AAB dosyası bulunamadı"
    AAB_OUT=""
fi

# ── ÇIKTI BİLGİLERİ ──────────────────────────────────────────
echo ""
echo "=========================================="
echo "  BUILD TAMAMLANDI ✓"
echo "=========================================="
echo ""
echo "APK: $APK_SIGNED"
echo "APK Boyutu: $(du -h "$APK_SIGNED" | cut -f1)"

if [ -n "$AAB_OUT" ] && [ -f "$AAB_OUT" ]; then
    echo "AAB: $AAB_OUT"
    echo "AAB Boyutu: $(du -h "$AAB_OUT" | cut -f1)"
fi

echo ""

# ── GITHUB ENVIRONMENT ───────────────────────────────────────
if [ -n "$GITHUB_ENV" ]; then
    echo "APK_FILE=$APK_SIGNED" >> "$GITHUB_ENV"
    [ -n "$AAB_OUT" ] && echo "AAB_FILE=$AAB_OUT" >> "$GITHUB_ENV"
    echo "BUILD_SUCCESS=true" >> "$GITHUB_ENV"
fi

# ── CLEANUP (Opsiyonel) ──────────────────────────────────────
# rm -rf "$BUILD_DIR"

echo "İşlem tamamlandı."
