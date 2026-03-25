#!/bin/bash
# ==============================================================================
# build_app.sh — PROFESYONEL ANDROID FABRİKASI (Firebase Dinamik Yama Destekli)
# Sürüm: 3.0 | Tarih: 2026 | Lokasyon: Cizre
# ==============================================================================
set -e

# ── 1. GİRİŞ VE LOGLAMA ──────────────────────────────────────────────────────
echo "==========================================================="
echo "  🛠️  UYGULAMA OLUŞTURUCU BAŞLATILDI"
echo "  📦 Hedef Paket: $PACKAGE_NAME"
echo "  🏷️  Uygulama Adı: $APP_NAME"
echo "==========================================================="

# ── 2. ORTAM DEĞİŞKENLERİ VE SDK YOLLARI ─────────────────────────────────────
# Android SDK yollarını otomatik bulur
ANDROID_SDK="${ANDROID_HOME:-/usr/local/lib/android/sdk}"
BUILD_TOOLS_DIR=$(ls -d "$ANDROID_SDK/build-tools/"* 2>/dev/null | sort -V | tail -1)
PLATFORM_TOOLS="$ANDROID_SDK/platform-tools"

if [ -z "$BUILD_TOOLS_DIR" ]; then
    echo "❌ HATA: Android Build Tools bulunamadı!"
    exit 1
fi

export PATH="$BUILD_TOOLS_DIR:$PLATFORM_TOOLS:$PATH"

# ── 3. ÇALIŞMA DİZİNİ HAZIRLIĞI ──────────────────────────────────────────────
# Her build için izole bir alan oluşturur
WORKSPACE="/tmp/factory_build_${APP_ID}_$$"
rm -rf "$WORKSPACE"
mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

PACKAGE_PATH=$(echo "$PACKAGE_NAME" | tr '.' '/')
mkdir -p app/src/main/java/$PACKAGE_PATH
mkdir -p app/src/main/res/{values,mipmap-hdpi,mipmap-mdpi,mipmap-xhdpi,mipmap-xxhdpi,mipmap-xxxhdpi,layout,xml}

# ── 4. DİNAMİK FIREBASE JSON YAMALAYICI (BİNLERCE UYGULAMA İÇİN KRİTİK) ──────
# Tek bir Firebase projesini binlerce pakete uydurur
echo "⚙️ Firebase JSON yamalanıyor..."

if [ -z "$GOOGLE_SERVICES_JSON" ]; then
    echo "❌ HATA: GOOGLE_SERVICES_JSON verisi sağlanmadı!"
    exit 1
fi

echo "$GOOGLE_SERVICES_JSON" > app/google-services.json

python3 -c "
import json
try:
    with open('app/google-services.json', 'r') as f:
        data = json.load(f)
    
    # Tüm client yapılandırmalarını senin paket adına zorla
    for client in data.get('client', []):
        client['client_info']['android_client_info']['package_name'] = '$PACKAGE_NAME'
    
    with open('app/google-services.json', 'w') as f:
        json.dump(data, f, indent=4)
    print('✅ JSON başarıyla yamalandı.')
except Exception as e:
    print(f'❌ JSON yamalanırken hata: {e}')
    exit(1)
"

# ── 5. GRADLE AYARLARI (AndroidX & Performans) ───────────────────────────────
cat > gradle.properties << EOF
android.useAndroidX=true
android.enableJetifier=true
org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=1024m
org.gradle.parallel=true
org.gradle.caching=true
EOF

cat > build.gradle << 'EOF'
buildscript {
    repositories { google(); mavenCentral() }
    dependencies {
        classpath 'com.android.tools.build:gradle:8.2.2'
        classpath 'com.google.gms:google-services:4.4.1'
    }
}
allprojects { repositories { google(); mavenCentral() } }
EOF

cat > settings.gradle << 'EOF'
rootProject.name = "app"
include ':app'
EOF

# ── 6. APP BUILD.GRADLE (NATIVE LIBS HATASI ÇÖZÜMÜ) ──────────────────────────
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

    # ÇAKIŞAN KÜTÜPHANELERİ VE DOSYALARI TEMİZLER
    packaging {
        resources {
            excludes += '/META-INF/{AL2.0,LGPL2.1}'
            excludes += 'META-INF/DEPENDENCIES'
            excludes += 'META-INF/LICENSE*'
            excludes += 'META-INF/NOTICE*'
            excludes += 'META-INF/*.kotlin_module'
            excludes += 'META-INF/ASL2.0'
        }
        jniLibs {
            pickFirsts += '**/libc++_shared.so'
        }
    }

    buildTypes {
        release {
            minifyEnabled false
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
    
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}

dependencies {
    implementation platform('com.google.firebase:firebase-bom:32.7.4')
    implementation 'com.google.firebase:firebase-firestore'
    implementation 'com.google.firebase:firebase-messaging'
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'androidx.multidex:multidex:2.0.1'
    implementation 'com.google.android.material:material:1.11.0'
}
EOF

# ── 7. JAVA KAYNAK KODLARI (WebView + Push Notification) ─────────────────────
cat > app/src/main/java/$PACKAGE_PATH/MainActivity.java << JAVA_EOF
package ${PACKAGE_NAME};

import android.app.Activity;
import android.os.Bundle;
import android.webkit.*;
import android.view.Window;
import android.view.WindowManager;
import com.google.firebase.messaging.FirebaseMessaging;

public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN, WindowManager.LayoutParams.FLAG_FULLSCREEN);

        WebView webView = new WebView(this);
        setContentView(webView);

        WebSettings s = webView.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setCacheMode(WebSettings.LOAD_DEFAULT);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);

        webView.setWebViewClient(new WebViewClient());
        webView.loadUrl("${CONTENT_URL:-https://google.com}");

        FirebaseMessaging.getInstance().subscribeToTopic("all_users");
    }
}
JAVA_EOF

# ── 8. ANDROID MANIFEST VE KAYNAKLAR ─────────────────────────────────────────
cat > app/src/main/AndroidManifest.xml << MANIFEST_EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="${PACKAGE_NAME}">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <application 
        android:label="${APP_NAME}" 
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="true"
        android:theme="@android:style/Theme.Material.Light.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true" android:configChanges="orientation|screenSize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
MANIFEST_EOF

echo '<?xml version="1.0" encoding="utf-8"?><resources><string name="app_name">'"${APP_NAME}"'</string></resources>' > app/src/main/res/values/strings.xml

# ── 9. GRADLE BUILD (APK OLUŞTURMA) ──────────────────────────────────────────
echo "🏗️  Gradle Build işlemi başlatılıyor..."
if ! gradle clean assembleRelease --stacktrace --no-daemon; then
    echo "❌ HATA: Gradle Build başarısız oldu!"
    exit 1
fi

# ── 10. İMZA VE ZIPALIGN İŞLEMLERİ ───────────────────────────────────────────
echo "✍️  APK imzalanıyor ve optimize ediliyor..."
RAW_APK="app/build/outputs/apk/release/app-release-unsigned.apk"
ALIGNED_APK="/tmp/${PACKAGE_NAME}_aligned.apk"
FINAL_APK="/tmp/${PACKAGE_NAME}_final.apk"
KEYSTORE="/tmp/production.jks"

# Eğer keystore yoksa oluştur (binlerce uygulama için tek bir tane yeterli)
if [ ! -f "$KEYSTORE" ]; then
    keytool -genkey -v -keystore "$KEYSTORE" -alias key0 -keyalg RSA -keysize 2048 -validity 10000 -storepass "android123" -keypass "android123" -dname "CN=Cizre, O=AppFactory, C=TR" -noprompt
fi

zipalign -v -p 4 "$RAW_APK" "$ALIGNED_APK"

apksigner sign --ks "$KEYSTORE" --ks-pass "pass:android123" --out "$FINAL_APK" "$ALIGNED_APK"

# ── 11. BİTİŞ ────────────────────────────────────────────────────────────────
if [ -f "$FINAL_APK" ]; then
    echo "==========================================================="
    echo "  ✅ İŞLEM BAŞARIYLA TAMAMLANDI"
    echo "  📂 APK Yolu: $FINAL_APK"
    echo "  📏 Boyut: $(du -h "$FINAL_APK" | cut -f1)"
    echo "==========================================================="
else
    echo "❌ HATA: Final APK oluşturulamadı."
    exit 1
fi
