#!/bin/bash
# ==============================================================================
# build_app.sh — MASTER FABRİKA (Gradle 9.x & Firebase Sync v4.0)
# ==============================================================================
set -e

echo "==========================================================="
echo "  🚀 SERİ ÜRETİM HATTI AKTİF"
echo "  📦 Paket: $PACKAGE_NAME"
echo "  📍 Konum: Cizre | Sistem: Gradle 9.4"
echo "==========================================================="

# ── 1. SDK VE PATH AYARLARI ──────────────────────────────────────────────────
ANDROID_SDK="${ANDROID_HOME:-/usr/local/lib/android/sdk}"
BUILD_TOOLS_DIR=$(ls -d "$ANDROID_SDK/build-tools/"* 2>/dev/null | sort -V | tail -1)
export PATH="$BUILD_TOOLS_DIR:$ANDROID_SDK/platform-tools:$PATH"

# ── 2. ÇALIŞMA ALANI TEMİZLİĞİ ───────────────────────────────────────────────
WORKSPACE="/tmp/factory_build_${APP_ID}_$$"
rm -rf "$WORKSPACE"
mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

PACKAGE_PATH=$(echo "$PACKAGE_NAME" | tr '.' '/')
mkdir -p app/src/main/java/$PACKAGE_PATH
mkdir -p app/src/main/res/{values,mipmap-hdpi,mipmap-mdpi,mipmap-xhdpi,mipmap-xxhdpi,mipmap-xxxhdpi}

# ── 3. FIREBASE JSON PATCHER (Dinamik Kimlik Enjeksiyonu) ────────────────────
echo "⚙️ Firebase JSON yapılandırılıyor..."
echo "$GOOGLE_SERVICES_JSON" > app/google-services.json

python3 -c "
import json, sys
try:
    with open('app/google-services.json', 'r') as f:
        data = json.load(f)
    # Tüm client kayıtlarını verilen PACKAGE_NAME ile değiştir
    for client in data.get('client', []):
        client['client_info']['android_client_info']['package_name'] = '$PACKAGE_NAME'
    with open('app/google-services.json', 'w') as f:
        json.dump(data, f, indent=4)
    print('✅ JSON başarıyla güncellendi.')
except Exception as e:
    print(f'❌ JSON hatası: {e}')
    sys.exit(1)
"

# ── 4. ROOT AYARLARI (Gradle 9 Uyumu) ────────────────────────────────────────
cat > gradle.properties << EOF
android.useAndroidX=true
android.enableJetifier=true
org.gradle.jvmargs=-Xmx4096m
# Gradle 9'un katı kuralları için ek ayarlar
android.nonTransitiveRClass=true
android.nonFinalResIds=false
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

# ── 5. APP BUILD.GRADLE (Kritik Sıralama Düzeltildi) ──────────────────────────
cat > app/build.gradle << EOF
plugins {
    id 'com.android.application'
    // Firebase eklentisi burada değil, en altta tanımlanacak (Mutation hatası çözümü)
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

    packaging {
        resources {
            excludes += '/META-INF/{AL2.0,LGPL2.1}'
            excludes += 'META-INF/DEPENDENCIES'
            excludes += 'META-INF/LICENSE*'
            excludes += 'META-INF/NOTICE*'
            excludes += 'META-INF/*.kotlin_module'
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
    // Firebase BOM en üste gelmeli
    implementation platform('com.google.firebase:firebase-bom:32.7.4')
    implementation 'com.google.firebase:firebase-firestore'
    implementation 'com.google.firebase:firebase-messaging'
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'androidx.multidex:multidex:2.0.1'
}

// KRİTİK: Google Services eklentisini en sona koyarak bağımlılık kilitlenmesini (Mutation Error) önlüyoruz
apply plugin: 'com.google.gms.google-services'
EOF

# ── 6. JAVA VE MANIFEST (Manifest Package Silindi) ───────────────────────────
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

# Manifest içindeki 'package' kısmını sildik, Gradle uyarısını çözdük
cat > app/src/main/AndroidManifest.xml << MANIFEST_EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
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

# ── 7. BUILD VE SONUÇ ────────────────────────────────────────────────────────
echo "🏗️  Gradle Build (v9.4) Başlatılıyor..."
# --no-daemon kullanarak her seferinde taze süreç başlatır, bellek hatalarını azaltır
gradle clean assembleRelease --stacktrace --no-daemon

APK_FINAL="app/build/outputs/apk/release/app-release-unsigned.apk"
if [ -f "$APK_FINAL" ]; then
    echo "==========================================================="
    echo "  ✅ BİN UYGULAMA İÇİN İLK APK HAZIR!"
    echo "  📂 Konum: $APK_FINAL"
    echo "==========================================================="
else
    echo "❌ HATA: APK üretilemedi!"
    exit 1
fi
