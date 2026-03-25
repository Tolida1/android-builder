#!/bin/bash
# ==============================================================================
# build_app.sh — MASTER FABRİKA v5.0 (Gradle 9.4 & AGP 8.2 Uyumlu)
# ==============================================================================
set -e

echo "==========================================================="
echo "  🚀 SERİ ÜRETİM HATTI AKTİF | SÜRÜM: 5.0"
echo "  📦 Paket: $PACKAGE_NAME"
echo "  📍 Cizre'den Selamlar | Sistem: Master Factory"
echo "==========================================================="

# ── 1. SDK VE PATH AYARLARI ──────────────────────────────────────────────────
ANDROID_SDK="${ANDROID_HOME:-/usr/local/lib/android/sdk}"
BUILD_TOOLS_DIR=$(ls -d "$ANDROID_SDK/build-tools/"* 2>/dev/null | sort -V | tail -1)
export PATH="$BUILD_TOOLS_DIR:$ANDROID_SDK/platform-tools:$PATH"

# ── 2. ÇALIŞMA ALANI HAZIRLIĞI ───────────────────────────────────────────────
WORKSPACE="/tmp/factory_build_${APP_ID}_$$"
rm -rf "$WORKSPACE"
mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

PACKAGE_PATH=$(echo "$PACKAGE_NAME" | tr '.' '/')
mkdir -p app/src/main/java/$PACKAGE_PATH
mkdir -p app/src/main/res/{values,mipmap-hdpi,mipmap-mdpi,mipmap-xhdpi,mipmap-xxhdpi,mipmap-xxxhdpi}

# ── 3. FIREBASE JSON PATCHER (Dinamik Paket Kimliği) ─────────────────────────
echo "⚙️ Firebase JSON yapılandırılıyor..."
echo "$GOOGLE_SERVICES_JSON" > app/google-services.json

python3 -c "
import json, sys
try:
    with open('app/google-services.json', 'r') as f:
        data = json.load(f)
    # Binlerce uygulama için tek JSON'u her pakete uyarla
    for client in data.get('client', []):
        client['client_info']['android_client_info']['package_name'] = '$PACKAGE_NAME'
    with open('app/google-services.json', 'w') as f:
        json.dump(data, f, indent=4)
    print('✅ Firebase JSON yamalandı: $PACKAGE_NAME')
except Exception as e:
    print(f'❌ JSON hatası: {e}')
    sys.exit(1)
"

# ── 4. GRADLE PROPERTIES (Kritik Ayarlar) ────────────────────────────────────
cat > gradle.properties << EOF
android.useAndroidX=true
android.enableJetifier=true
org.gradle.jvmargs=-Xmx4096m
# Gradle 9 izolasyon ayarları
android.nonTransitiveRClass=true
android.nonFinalResIds=false
EOF

# ── 5. ANA BUILD.GRADLE (Modern Plugins Bloğu) ───────────────────────────────
cat > build.gradle << 'EOF'
// Bağımlılık kilitlenmesini önlemek için plugin sürümlerini burada tanımlıyoruz
plugins {
    id 'com.android.application' version '8.2.2' apply false
    id 'com.google.gms.google-services' version '4.4.1' apply false
}
EOF

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

# ── 6. APP BUILD.GRADLE (Hatasız Yapılandırma) ───────────────────────────────
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
    implementation platform('com.google.firebase:firebase-bom:32.7.4')
    implementation 'com.google.firebase:firebase-firestore'
    implementation 'com.google.firebase:firebase-messaging'
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'androidx.multidex:multidex:2.0.1'
}
EOF

# ── 7. JAVA KODU VE MANIFEST ─────────────────────────────────────────────────
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
        wv.getSettings().setDomStorageEnabled(true);
        wv.setWebViewClient(new WebViewClient());
        wv.loadUrl("${CONTENT_URL:-https://google.com}");
    }
}
JAVA_EOF

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

# ── 8. BUILD SÜRECİ ──────────────────────────────────────────────────────────
echo "🏗️  Gradle 9.4 Build İşlemi Başlatılıyor..."
# --no-daemon ve --info ile daha temiz ve detaylı build
gradle clean assembleRelease --stacktrace --no-daemon

# ── 9. SONUÇ KONTROLÜ ────────────────────────────────────────────────────────
APK_FINAL="app/build/outputs/apk/release/app-release-unsigned.apk"
if [ -f "$APK_FINAL" ]; then
    echo "==========================================================="
    echo "  ✅ TEBRİKLER AYHAN! APK HAZIR"
    echo "  📂 Konum: $APK_FINAL"
    echo "==========================================================="
else
    echo "❌ HATA: APK üretilemedi. Logları kontrol et."
    exit 1
fi
