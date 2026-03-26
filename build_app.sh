#!/bin/bash
# ==============================================================================
# build_app.sh — ExoPlayer + Firebase + M3U Player
# Gradle 8.4 + AGP 8.2.2 + GMS 4.3.15
# ==============================================================================
set -e

echo "=========================================="
echo "  BUILD: $APP_NAME ($PACKAGE_NAME)"
echo "  Owner: $OWNER_ID | App: $APP_ID"
echo "=========================================="

ANDROID_SDK="${ANDROID_HOME:-/usr/local/lib/android/sdk}"
BUILD_TOOLS_DIR=$(ls -d "$ANDROID_SDK/build-tools/"* 2>/dev/null | sort -V | tail -1)
export PATH="$BUILD_TOOLS_DIR:$ANDROID_SDK/platform-tools:$PATH"

# Gradle 8.4
GRADLE_VERSION="7.6.4"
GRADLE_HOME="/opt/gradle-${GRADLE_VERSION}"
if [ ! -f "$GRADLE_HOME/bin/gradle" ]; then
    wget -q "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" -O /tmp/gradle.zip
    sudo unzip -q /tmp/gradle.zip -d /opt/
    rm -f /tmp/gradle.zip
fi
GRADLE="$GRADLE_HOME/bin/gradle"

# Workspace
WORKSPACE="/tmp/build_${APP_ID}_$$"
rm -rf "$WORKSPACE"; mkdir -p "$WORKSPACE"; cd "$WORKSPACE"

PACKAGE_PATH=$(echo "$PACKAGE_NAME" | tr '.' '/')
mkdir -p app/src/main/java/$PACKAGE_PATH
mkdir -p app/src/main/res/{values,mipmap-hdpi,mipmap-mdpi,mipmap-xhdpi,mipmap-xxhdpi,mipmap-xxxhdpi}

# Google Services JSON
echo "$GOOGLE_SERVICES_JSON" > app/google-services.json
python3 - << PYEOF
import json
with open('app/google-services.json','r') as f: data=json.load(f)
for c in data.get('client',[]): c['client_info']['android_client_info']['package_name']='${PACKAGE_NAME}'
with open('app/google-services.json','w') as f: json.dump(data,f,indent=2)
print("google-services.json updated")
PYEOF

# Java files
for jf in MainActivity AppFirebaseMessagingService PlayerActivity ContentAdapter M3uParser; do
    src="$GITHUB_WORKSPACE/${jf}.java"
    dst="app/src/main/java/$PACKAGE_PATH/${jf}.java"
    if [ -f "$src" ]; then
        sed "s/PACKAGE_PLACEHOLDER/${PACKAGE_NAME}/g" "$src" > "$dst"
        # Replace other placeholders in MainActivity
        if [ "$jf" = "MainActivity" ]; then
            sed -i "s/OWNER_ID_PLACEHOLDER/${OWNER_ID}/g" "$dst"
            sed -i "s/APP_ID_PLACEHOLDER/${APP_ID}/g" "$dst"
            sed -i "s/APP_TOPIC_PLACEHOLDER/app_${APP_ID}/g" "$dst"
            sed -i "s|CONTENT_URL_PLACEHOLDER|${CONTENT_URL:-https://example.com}|g" "$dst"
        fi
    fi
done

# AndroidManifest
cat > app/src/main/AndroidManifest.xml << MANIFEST_EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="${APP_NAME}"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:usesCleartextTraffic="true"
        android:hardwareAccelerated="true"
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
        <activity
            android:name=".PlayerActivity"
            android:exported="false"
            android:screenOrientation="sensorLandscape"
            android:configChanges="orientation|screenSize|keyboardHidden"
            android:windowSoftInputMode="adjustNothing" />
        <service android:name=".AppFirebaseMessagingService" android:exported="false">
            <intent-filter>
                <action android:name="com.google.firebase.MESSAGING_EVENT" />
            </intent-filter>
        </service>
    </application>
</manifest>
MANIFEST_EOF

# Resources
cat > app/src/main/res/values/colors.xml << EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="primaryColor">${PRIMARY_COLOR:-#6c63ff}</color>
    <color name="primaryDarkColor">${PRIMARY_DARK_COLOR:-#5a52d5}</color>
    <color name="accentColor">${ACCENT_COLOR:-#ff6584}</color>
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
        <item name="android:windowBackground">@android:color/black</item>
    </style>
</resources>
EOF

# Icons
sudo apt-get install -y -qq imagemagick 2>/dev/null
generate_icon() {
    local sz=$1 dpi=$2
    if [ -f /tmp/icon_source.png ]; then
        convert /tmp/icon_source.png -resize ${sz}x${sz} app/src/main/res/mipmap-$dpi/ic_launcher.png
    else
        convert -size ${sz}x${sz} xc:"${PRIMARY_COLOR:-#6c63ff}" -fill white -gravity center \
            -pointsize $((sz/3)) -annotate 0 "${APP_NAME:0:1}" app/src/main/res/mipmap-$dpi/ic_launcher.png
    fi
    cp app/src/main/res/mipmap-$dpi/ic_launcher.png app/src/main/res/mipmap-$dpi/ic_launcher_round.png
}
[ -n "$ICON_URL" ] && wget -q "$ICON_URL" -O /tmp/icon_source.png 2>/dev/null || true
generate_icon 72 hdpi; generate_icon 48 mdpi; generate_icon 96 xhdpi
generate_icon 144 xxhdpi; generate_icon 192 xxxhdpi

# Gradle Properties
cat > gradle.properties << 'EOF'
android.useAndroidX=true
android.enableJetifier=false
org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=512m
android.nonTransitiveRClass=true
kotlin.stdlib.default.dependency=false
EOF

# Settings
cat > settings.gradle << 'EOF'
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "creatorapp"
include ':app'
EOF

# Root build.gradle — AGP 7.4.2 + GMS 4.3.15 (media3 ile uyumlu en stabil kombinasyon)
cat > build.gradle << 'EOF'
buildscript {
    repositories { google(); mavenCentral() }
    dependencies {
        classpath 'com.android.tools.build:gradle:7.4.2'
        classpath 'com.google.gms:google-services:4.3.15'
    }
}
EOF

# App build.gradle
cat > app/build.gradle << EOF
apply plugin: 'com.android.application'
apply plugin: 'com.google.gms.google-services'

android {
    namespace '${PACKAGE_NAME}'
    compileSdkVersion 34

    defaultConfig {
        applicationId '${PACKAGE_NAME}'
        minSdkVersion 21
        targetSdkVersion 34
        versionCode ${VERSION_CODE:-1}
        versionName '${VERSION_NAME:-1.0}'
        multiDexEnabled true
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_11
        targetCompatibility JavaVersion.VERSION_11
    }

    buildTypes {
        release { minifyEnabled false }
    }

    packagingOptions {
        resources {
            excludes += ['META-INF/DEPENDENCIES','META-INF/LICENSE',
                         'META-INF/NOTICE','META-INF/*.kotlin_module',
                         'META-INF/AL2.0','META-INF/LGPL2.1']
        }
    }
}

configurations.all {
    resolutionStrategy {
        force 'org.jetbrains.kotlin:kotlin-stdlib:1.8.22'
        force 'org.jetbrains.kotlin:kotlin-stdlib-common:1.8.22'
        exclude group: 'org.jetbrains.kotlin', module: 'kotlin-stdlib-jdk7'
        exclude group: 'org.jetbrains.kotlin', module: 'kotlin-stdlib-jdk8'
    }
}

dependencies {
    // Firebase
    implementation platform('com.google.firebase:firebase-bom:32.7.4')
    implementation 'com.google.firebase:firebase-firestore'
    implementation 'com.google.firebase:firebase-messaging'

    // AndroidX
    implementation 'androidx.core:core:1.9.0'
    implementation 'androidx.recyclerview:recyclerview:1.3.0'
    implementation 'androidx.multidex:multidex:2.0.1'

    // ExoPlayer Media3
    implementation 'androidx.media3:media3-exoplayer:1.2.1'
    implementation 'androidx.media3:media3-exoplayer-hls:1.2.1'
    implementation 'androidx.media3:media3-exoplayer-dash:1.2.1'
    implementation 'androidx.media3:media3-exoplayer-rtsp:1.2.1'
    implementation 'androidx.media3:media3-exoplayer-smoothstreaming:1.2.1'
    implementation 'androidx.media3:media3-ui:1.2.1'
    implementation 'androidx.media3:media3-datasource-okhttp:1.2.1'

    // OkHttp
    implementation 'com.squareup.okhttp3:okhttp:4.12.0'

    // Kotlin
    implementation 'org.jetbrains.kotlin:kotlin-stdlib:1.8.22'
}
EOF
}
EOF

# Gradle wrapper
mkdir -p gradle/wrapper
cat > gradle/wrapper/gradle-wrapper.properties << EOF
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\\://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

# Build
echo "Gradle build başlıyor..."
$GRADLE assembleRelease --no-daemon --no-configuration-cache -q 2>&1 | tail -30

APK_IN="$WORKSPACE/app/build/outputs/apk/release/app-release-unsigned.apk"
APK_OUT="/tmp/${PACKAGE_NAME}_v${VERSION_CODE:-1}.apk"
AAB_OUT="/tmp/${PACKAGE_NAME}_v${VERSION_CODE:-1}.aab"

[ -f "$APK_IN" ] || { echo "❌ APK bulunamadı"; exit 1; }

keytool -genkey -v -keystore /tmp/ks.jks -alias release -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass android -keypass android -dname "CN=Android,OU=Android,O=Android,L=Android,S=Android,C=US" -noprompt 2>/dev/null

"$BUILD_TOOLS_DIR/zipalign" -v 4 "$APK_IN" /tmp/aligned.apk
"$BUILD_TOOLS_DIR/apksigner" sign --ks /tmp/ks.jks --ks-key-alias release \
  --ks-pass pass:android --key-pass pass:android --out "$APK_OUT" /tmp/aligned.apk

# AAB
$GRADLE bundleRelease --no-daemon --no-configuration-cache -q 2>&1 | tail -10
AAB_IN="$WORKSPACE/app/build/outputs/bundle/release/app-release.aab"
[ -f "$AAB_IN" ] && cp "$AAB_IN" "$AAB_OUT"

echo "APK_FILE=$APK_OUT" >> $GITHUB_ENV
echo "AAB_FILE=$AAB_OUT" >> $GITHUB_ENV
echo "=========================================="
echo "✅ BUILD TAMAMLANDI — APK: $(du -sh $APK_OUT | cut -f1)"
echo "=========================================="
