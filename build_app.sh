#!/bin/bash
# ============================================================
# build_app.sh — Firebase Entegreli Android Builder
# ============================================================
set -e

echo "=========================================="
echo "  BUILD: $APP_NAME ($PACKAGE_NAME)"
echo "  Owner: $OWNER_ID | App: $APP_ID"
echo "=========================================="

BUILD_DIR="/tmp/build_${APP_ID}_$$"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

PACKAGE_PATH=$(echo "$PACKAGE_NAME" | tr '.' '/')
mkdir -p app/src/main/java/$PACKAGE_PATH
mkdir -p app/src/main/res/{values,mipmap-hdpi,mipmap-mdpi,mipmap-xhdpi,mipmap-xxhdpi,mipmap-xxxhdpi}

# ── JAVA DOSYALARI ───────────────────────────────────────────
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
        android:label="${APP_NAME}"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/AppTheme">
        <activity android:name=".MainActivity" android:exported="true" android:launchMode="singleTop">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <service android:name=".AppFirebaseMessagingService" android:exported="false">
            <intent-filter>
                <action android:name="com.google.firebase.MESSAGING_EVENT" />
            </intent-filter>
        </service>
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

# ── İKON ─────────────────────────────────────────────────────
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

# ── GOOGLE-SERVICES.JSON ─────────────────────────────────────
echo "$GOOGLE_SERVICES_JSON" > app/google-services.json

# ── GRADLE ───────────────────────────────────────────────────
cat > build.gradle << 'EOF'
buildscript {
    repositories { google(); mavenCentral() }
    dependencies {
        classpath 'com.android.tools.build:gradle:8.2.0'
        classpath 'com.google.gms:google-services:4.4.1'
    }
}
allprojects { repositories { google(); mavenCentral() } }
EOF

cat > app/build.gradle << EOF
apply plugin: 'com.android.application'
apply plugin: 'com.google.gms.google-services'

android {
    compileSdkVersion 34
    defaultConfig {
        applicationId "${PACKAGE_NAME}"
        minSdkVersion 21
        targetSdkVersion 34
        versionCode ${VERSION_CODE:-1}
        versionName "${VERSION_NAME:-1.0}"
    }
    buildTypes { release { minifyEnabled false } }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}

dependencies {
    implementation platform('com.google.firebase:firebase-bom:32.7.4')
    implementation 'com.google.firebase:firebase-firestore'
    implementation 'com.google.firebase:firebase-messaging'
    implementation 'androidx.core:core:1.12.0'
}
EOF

cat > settings.gradle << 'EOF'
include ':app'
EOF

mkdir -p gradle/wrapper
cat > gradle/wrapper/gradle-wrapper.properties << 'EOF'
distributionUrl=https\://services.gradle.org/distributions/gradle-8.4-bin.zip
EOF

# ── BUILD + İMZALA ───────────────────────────────────────────
echo "Gradle build başlıyor..."
gradle assembleRelease bundleRelease --no-daemon -q 2>&1 | tail -20

APK_OUT="/tmp/${PACKAGE_NAME}_v${VERSION_CODE:-1}.apk"
AAB_OUT="/tmp/${PACKAGE_NAME}_v${VERSION_CODE:-1}.aab"

keytool -genkey -v \
  -keystore /tmp/ks.jks -alias release \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass android -keypass android \
  -dname "CN=Android,OU=Android,O=Android,L=Android,S=Android,C=US" \
  -noprompt 2>/dev/null

zipalign -v 4 "$BUILD_DIR/app/build/outputs/apk/release/app-release-unsigned.apk" /tmp/aligned.apk
apksigner sign \
  --ks /tmp/ks.jks --ks-key-alias release \
  --ks-pass pass:android --key-pass pass:android \
  --out "$APK_OUT" /tmp/aligned.apk

cp "$BUILD_DIR/app/build/outputs/bundle/release/app-release.aab" "$AAB_OUT"

echo "APK_FILE=$APK_OUT" >> $GITHUB_ENV
echo "AAB_FILE=$AAB_OUT" >> $GITHUB_ENV
echo "BUILD TAMAMLANDI ✓"
