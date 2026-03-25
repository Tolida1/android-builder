#!/bin/bash
# ==============================================================================
# build_app.sh — PROFESYONEL ANDROID FABRİKASI (Hatasız Seri Üretim)
# Sürüm: 3.1 | Durum: Tüm Gradle Karakter Hataları Giderildi
# ==============================================================================
set -e

echo "==========================================================="
echo "  🛠️  UYGULAMA FABRİKASI ÇALIŞIYOR"
echo "  📦 Paket: $PACKAGE_NAME"
echo "  🏷️  Ad: $APP_NAME"
echo "==========================================================="

# ── 1. ORTAM VE SDK YOLLARI ──────────────────────────────────────────────────
ANDROID_SDK="${ANDROID_HOME:-/usr/local/lib/android/sdk}"
BUILD_TOOLS_DIR=$(ls -d "$ANDROID_SDK/build-tools/"* 2>/dev/null | sort -V | tail -1)
export PATH="$BUILD_TOOLS_DIR:$ANDROID_SDK/platform-tools:$PATH"

if [ -z "$BUILD_TOOLS_DIR" ]; then
    echo "❌ HATA: Android Build Tools bulunamadı!"
    exit 1
fi

# ── 2. ÇALIŞMA ALANI HAZIRLIĞI ──────────────────────────────────────────────
WORKSPACE="/tmp/factory_build_${APP_ID}_$$"
rm -rf "$WORKSPACE"
mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

PACKAGE_PATH=$(echo "$PACKAGE_NAME" | tr '.' '/')
mkdir -p app/src/main/java/$PACKAGE_PATH
mkdir -p app/src/main/res/{values,mipmap-hdpi,mipmap-mdpi,mipmap-xhdpi,mipmap-xxhdpi,mipmap-xxxhdpi,layout}

# ── 3. FIREBASE JSON PATCHER (Dinamik Paket İsmi Değiştirici) ────────────────
echo "⚙️ Firebase JSON yamalanıyor..."
echo "$GOOGLE_SERVICES_JSON" > app/google-services.json

python3 -c "
import json, sys
try:
    with open('app/google-services.json', 'r') as f:
        data = json.load(f)
    for client in data.get('client', []):
        client['client_info']['android_client_info']['package_name'] = '$PACKAGE_NAME'
    with open('app/google-services.json', 'w') as f:
        json.dump(data, f, indent=4)
    print('✅ Firebase JSON paket adı uyarlandı.')
except Exception as e:
    print(f'❌ JSON hatası: {e}')
    sys.exit(1)
"

# ── 4. AYAR DOSYALARI (AndroidX & Gradle) ────────────────────────────────────
cat > gradle.properties << EOF
android.useAndroidX=true
android.enableJetifier=true
org.gradle.jvmargs=-Xmx4096m
EOF

cat > build.gradle << 'EOF'
// Kök build dosyası
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
// Proje ayarları
rootProject.name = "app"
include ':app'
EOF

# ── 5. APP BUILD.GRADLE (KRİTİK HATA DÜZELTİLDİ) ─────────────────────────────
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

    // ÇAKIŞAN KÜTÜPHANELERİ VE DOSYALARI TEMİZLER (DÜZELTİLDİ)
    packaging {
        resources {
            excludes += '/META-INF/{AL2.0,LGPL2.1}'
            excludes += 'META-INF/DEPENDENCIES'
            excludes += 'META-INF/LICENSE*'
            excludes += 'META-INF/NOTICE*'
            excludes += 'META-INF/*.kotlin_module'
        }
        jniLibs {
            // libc++_shared.so çakışmasını engeller
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
}
EOF

# ── 6. JAVA VE MANIFEST ──────────────────────────────────────────────────────
cat > app/src/main/java/$PACKAGE_PATH/MainActivity.java << JAVA_EOF
package ${PACKAGE_NAME};
import android.app.Activity;
import android.os.Bundle;
import android.webkit.*;

public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        WebView wv = new WebView(this);
        setContentView(wv);
        wv.getSettings().setJavaScriptEnabled(true);
        wv.setWebViewClient(new WebViewClient());
        wv.loadUrl("${CONTENT_URL:-https://google.com}");
    }
}
JAVA_EOF

cat > app/src/main/AndroidManifest.xml << MANIFEST_EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="${PACKAGE_NAME}">
    <uses-permission android:name="android.permission.INTERNET" />
    <application android:label="${APP_NAME}" android:icon="@mipmap/ic_launcher" android:usesCleartextTraffic="true">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
MANIFEST_EOF

echo '<?xml version="1.0" encoding="utf-8"?><resources><string name="app_name">'"${APP_NAME}"'</string></resources>' > app/src/main/res/values/strings.xml

# ── 7. BUILD SÜRECİ ──────────────────────────────────────────────────────────
echo "🚀 Build başlatılıyor..."
gradle clean assembleRelease --stacktrace --no-daemon

# ── 8. SONUÇ VE İMZA KONTROLÜ ────────────────────────────────────────────────
APK_RAW="app/build/outputs/apk/release/app-release-unsigned.apk"
if [ -f "$APK_RAW" ]; then
    echo "==========================================================="
    echo "  ✅ APK BAŞARIYLA OLUŞTURULDU"
    echo "  📂 Konum: $APK_RAW"
    echo "==========================================================="
else
    echo "❌ HATA: APK oluşturulamadı!"
    exit 1
fi
