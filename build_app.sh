#!/bin/bash
# ==============================================================================
# build_app.sh — Stabil Kombinasyon
# Gradle 8.4 + AGP 8.2.2 + GMS 4.3.15 (Mutation hatası yok)
# ==============================================================================
set -e

echo "=========================================="
echo "  BUILD: $APP_NAME ($PACKAGE_NAME)"
echo "  Owner: $OWNER_ID | App: $APP_ID"
echo "=========================================="

# --- 1. ANDROID SDK YOLLARI ---
ANDROID_SDK="${ANDROID_HOME:-/usr/local/lib/android/sdk}"
BUILD_TOOLS_DIR=$(ls -d "$ANDROID_SDK/build-tools/"* 2>/dev/null | sort -V | tail -1)
export PATH="$BUILD_TOOLS_DIR:$ANDROID_SDK/platform-tools:$PATH"
echo "Build tools: $BUILD_TOOLS_DIR"

# --- 2. GRADLE 8.4 KUR (sistem Gradle 9 olabilir, biz 8.4 kullanacağız) ---
GRADLE_VERSION="8.4"
GRADLE_HOME="/opt/gradle-${GRADLE_VERSION}"
if [ ! -f "$GRADLE_HOME/bin/gradle" ]; then
    echo "Gradle ${GRADLE_VERSION} indiriliyor..."
    wget -q "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" -O /tmp/gradle.zip
    sudo unzip -q /tmp/gradle.zip -d /opt/
    sudo mv /opt/gradle-${GRADLE_VERSION} $GRADLE_HOME 2>/dev/null || true
    rm -f /tmp/gradle.zip
fi
GRADLE="$GRADLE_HOME/bin/gradle"
echo "Gradle: $($GRADLE --version | head -1)"

# --- 3. ÇALIŞMA ALANI ---
WORKSPACE="/tmp/build_${APP_ID}_$$"
rm -rf "$WORKSPACE"
mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

PACKAGE_PATH=$(echo "$PACKAGE_NAME" | tr '.' '/')
mkdir -p app/src/main/java/$PACKAGE_PATH
mkdir -p app/src/main/res/{values,mipmap-hdpi,mipmap-mdpi,mipmap-xhdpi,mipmap-xxhdpi,mipmap-xxxhdpi}

# --- 4. GOOGLE-SERVICES.JSON (paket adını güncelle) ---
echo "$GOOGLE_SERVICES_JSON" > app/google-services.json
python3 - << PYEOF
import json
with open('app/google-services.json', 'r') as f:
    data = json.load(f)
for client in data.get('client', []):
    client['client_info']['android_client_info']['package_name'] = '${PACKAGE_NAME}'
with open('app/google-services.json', 'w') as f:
    json.dump(data, f, indent=2)
print("google-services.json guncellendi")
PYEOF

# --- 5. GRADLE PROPERTIES ---
cat > gradle.properties << 'EOF'
android.useAndroidX=true
android.enableJetifier=true
org.gradle.jvmargs=-Xmx3072m -XX:MaxMetaspaceSize=512m
android.nonTransitiveRClass=true
EOF

# --- 6. SETTINGS.GRADLE ---
cat > settings.gradle << 'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "creatorapp"
include ':app'
EOF

# --- 7. ROOT BUILD.GRADLE ---
# AGP 8.2.2 + GMS 4.3.15 kombinasyonu Gradle 8.4 ile sorunsuz çalışır
cat > build.gradle << 'EOF'
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:8.2.2'
        classpath 'com.google.gms:google-services:4.3.15'
    }
}
EOF

# --- 8. APP BUILD.GRADLE ---
cat > app/build.gradle << EOF
apply plugin: 'com.android.application'
apply plugin: 'com.google.gms.google-services'

android {
    namespace '${PACKAGE_NAME}'
    compileSdk 34

    defaultConfig {
        applicationId '${PACKAGE_NAME}'
        minSdk 21
        targetSdk 34
        versionCode ${VERSION_CODE:-1}
        versionName '${VERSION_NAME:-1.0}'
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }

    buildTypes {
        release {
            minifyEnabled false
        }
    }

    packaging {
        resources {
            excludes += ['META-INF/DEPENDENCIES', 'META-INF/LICENSE', 'META-INF/NOTICE']
        }
    }
}

dependencies {
    // Firebase BOM — 32.7.4 GMS 4.3.x ile uyumlu
    implementation platform('com.google.firebase:firebase-bom:32.7.4')
    implementation 'com.google.firebase:firebase-firestore'
    implementation 'com.google.firebase:firebase-messaging'
    implementation 'androidx.core:core:1.12.0'
    implementation 'androidx.appcompat:appcompat:1.6.1'
}
EOF

# --- 9. GRADLE WRAPPER ---
mkdir -p gradle/wrapper
cat > gradle/wrapper/gradle-wrapper.properties << EOF
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\\://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

# --- 10. JAVA DOSYALARI ---
sed -e "s/PACKAGE_PLACEHOLDER/${PACKAGE_NAME}/g" \
    -e "s/OWNER_ID_PLACEHOLDER/${OWNER_ID}/g" \
    -e "s/APP_ID_PLACEHOLDER/${APP_ID}/g" \
    -e "s/APP_TOPIC_PLACEHOLDER/app_${APP_ID}/g" \
    -e "s|CONTENT_URL_PLACEHOLDER|${CONTENT_URL:-https://example.com}|g" \
    "$GITHUB_WORKSPACE/MainActivity.java" \
    > app/src/main/java/$PACKAGE_PATH/MainActivity.java

sed "s/PACKAGE_PLACEHOLDER/${PACKAGE_NAME}/g" \
    "$GITHUB_WORKSPACE/AppFirebaseMessagingService.java" \
    > app/src/main/java/$PACKAGE_PATH/AppFirebaseMessagingService.java

# --- 11. ANDROIDMANIFEST ---
cat > app/src/main/AndroidManifest.xml << MANIFEST_EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="${APP_NAME}"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:usesCleartextTraffic="true"
        android:theme="@style/AppTheme">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop">
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
    </application>
</manifest>
MANIFEST_EOF

# --- 12. RENKLER & STİLLER ---
cat > app/src/main/res/values/colors.xml << EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="primaryColor">${PRIMARY_COLOR:-#2196F3}</color>
    <color name="primaryDarkColor">${PRIMARY_DARK_COLOR:-#1565C0}</color>
    <color name="accentColor">${ACCENT_COLOR:-#FF4081}</color>
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
    </style>
</resources>
EOF

# --- 13. İKON ---
sudo apt-get install -y -qq imagemagick 2>/dev/null

generate_icon() {
    local size=$1 dpi=$2
    if [ -f /tmp/icon_source.png ]; then
        convert /tmp/icon_source.png -resize ${size}x${size} \
            app/src/main/res/mipmap-$dpi/ic_launcher.png
    else
        convert -size ${size}x${size} xc:"${PRIMARY_COLOR:-#2196F3}" \
            -fill white -gravity center \
            -pointsize $((size/3)) -annotate 0 "${APP_NAME:0:1}" \
            app/src/main/res/mipmap-$dpi/ic_launcher.png
    fi
    cp app/src/main/res/mipmap-$dpi/ic_launcher.png \
       app/src/main/res/mipmap-$dpi/ic_launcher_round.png
}

[ -n "$ICON_URL" ] && wget -q "$ICON_URL" -O /tmp/icon_source.png 2>/dev/null || true

generate_icon 72  hdpi
generate_icon 48  mdpi
generate_icon 96  xhdpi
generate_icon 144 xxhdpi
generate_icon 192 xxxhdpi

# --- 14. BUILD ---
echo "Gradle build başlıyor (Gradle 8.4 + AGP 8.2.2 + GMS 4.3.15)..."
$GRADLE assembleRelease --no-daemon --no-configuration-cache -q 2>&1 | tail -30

# --- 15. İMZALA ---
APK_IN="$WORKSPACE/app/build/outputs/apk/release/app-release-unsigned.apk"
APK_OUT="/tmp/${PACKAGE_NAME}_v${VERSION_CODE:-1}.apk"
AAB_OUT="/tmp/${PACKAGE_NAME}_v${VERSION_CODE:-1}.aab"

if [ ! -f "$APK_IN" ]; then
    echo "❌ APK bulunamadı: $APK_IN"
    exit 1
fi

keytool -genkey -v \
  -keystore /tmp/ks.jks -alias release \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass android -keypass android \
  -dname "CN=Android,OU=Android,O=Android,L=Android,S=Android,C=US" \
  -noprompt 2>/dev/null

"$BUILD_TOOLS_DIR/zipalign" -v 4 "$APK_IN" /tmp/aligned.apk

"$BUILD_TOOLS_DIR/apksigner" sign \
  --ks /tmp/ks.jks \
  --ks-key-alias release \
  --ks-pass pass:android \
  --key-pass pass:android \
  --out "$APK_OUT" \
  /tmp/aligned.apk

# AAB build
$GRADLE bundleRelease --no-daemon --no-configuration-cache -q 2>&1 | tail -10
AAB_IN="$WORKSPACE/app/build/outputs/bundle/release/app-release.aab"
[ -f "$AAB_IN" ] && cp "$AAB_IN" "$AAB_OUT"

echo "APK_FILE=$APK_OUT" >> $GITHUB_ENV
echo "AAB_FILE=$AAB_OUT" >> $GITHUB_ENV

echo "=========================================="
echo "✅ BUILD TAMAMLANDI"
echo "   APK: $APK_OUT"
echo "   AAB: $AAB_OUT"
echo "=========================================="
