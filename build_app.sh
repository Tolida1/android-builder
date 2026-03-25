#!/bin/bash
# ==============================================================================
# build_app.sh — MASTER FACTORY v6.0 (Gradle 9.4 & AGP 8.2 & GS 4.4.1)
# ==============================================================================
set -e

# --- 1. SİSTEM YOLLARI VE HAZIRLIK ---
ANDROID_SDK="${ANDROID_HOME:-/usr/local/lib/android/sdk}"
BUILD_TOOLS_DIR=$(ls -d "$ANDROID_SDK/build-tools/"* 2>/dev/null | sort -V | tail -1)
export PATH="$BUILD_TOOLS_DIR:$ANDROID_SDK/platform-tools:$PATH"

# --- 2. İZOLASYONLU ÇALIŞMA ALANI ---
WORKSPACE="/tmp/factory_build_${APP_ID}_$$"
rm -rf "$WORKSPACE"
mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

PACKAGE_PATH=$(echo "$PACKAGE_NAME" | tr '.' '/')
mkdir -p app/src/main/java/$PACKAGE_PATH
mkdir -p app/src/main/res/{values,mipmap-hdpi,mipmap-mdpi,mipmap-xhdpi,mipmap-xxhdpi,mipmap-xxxhdpi}

# --- 3. FIREBASE JSON PATCHER (PYTHON) ---
# Tek bir Firebase projesini her pakete uydurmak için dinamik yama yapar
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
except Exception as e:
    sys.exit(1)
"

# --- 4. GRADLE PROPERTIES ---
# Hafıza ve modern Gradle 9 izolasyon ayarları
cat > gradle.properties << EOF
android.useAndroidX=true
android.enableJetifier=true
org.gradle.jvmargs=-Xmx4096m
android.nonTransitiveRClass=true
android.nonFinalResIds=false
android.defaults.buildfeatures.buildconfig=true
EOF

# --- 5. SETTINGS GRADLE (KRİTİK ÇÖZÜM) ---
# Bağımlılık çözümlemesini merkezi hale getirerek eklenti çakışmasını önler
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

# --- 6. ROOT BUILD.GRADLE ---
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
EOF

# --- 7. APP BUILD.GRADLE (MUTATION ERROR FIX) ---
cat > app/build.gradle << EOF
apply plugin: 'com.android.application'
apply plugin: 'com.google.gms.google-services'

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

// Google Services'in classpath'i bozmasını engellemek için versiyon kontrolünü kapatıyoruz
googleServices { disableVersionCheck = true }
EOF

# --- 8. JAVA VE MANIFEST ---
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

# --- 9. BUILD ---
echo "🏗️ Gradle 9.4 Serbest Stil Build Başlatılıyor..."
# --no-daemon kullanarak her build'de taze bir JVM başlatıyoruz
gradle clean assembleRelease --stacktrace --no-daemon

# --- 10. ÇIKTI ---
APK_OUT="app/build/outputs/apk/release/app-release-unsigned.apk"
if [ -f "$APK_OUT" ]; then
    echo "=========================================="
    echo "✅ FABRİKA APK'YI BASTI: $APK_OUT"
    echo "=========================================="
else
    echo "❌ HATA: Build başarısız."
    exit 1
fi
