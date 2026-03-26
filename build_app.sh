#!/bin/bash
set -e

echo "BUILD: $APP_NAME ($PACKAGE_NAME)"

# SDK paths
ANDROID_SDK="${ANDROID_HOME:-/usr/local/lib/android/sdk}"
BUILD_TOOLS_DIR=$(ls -d "$ANDROID_SDK/build-tools/"* 2>/dev/null | sort -V | tail -1)
export PATH="$BUILD_TOOLS_DIR:$ANDROID_SDK/platform-tools:$PATH"
echo "Build tools: $BUILD_TOOLS_DIR"

# Gradle 7.6.4
GV="7.6.4"
GRADLE="/opt/gradle-${GV}/bin/gradle"
if [ ! -f "$GRADLE" ]; then
  wget -q "https://services.gradle.org/distributions/gradle-${GV}-bin.zip" -O /tmp/g.zip
  sudo unzip -q /tmp/g.zip -d /opt/
  rm -f /tmp/g.zip
fi

# Workspace
WS="/tmp/build_${APP_ID}_$$"
rm -rf "$WS" && mkdir -p "$WS" && cd "$WS"

PKG_PATH=$(echo "$PACKAGE_NAME" | tr '.' '/')
mkdir -p app/src/main/java/$PKG_PATH
mkdir -p app/src/main/res/{values,mipmap-hdpi,mipmap-mdpi,mipmap-xhdpi,mipmap-xxhdpi,mipmap-xxxhdpi}

# ── google-services.json ─────────────────────────────────────
echo "$GOOGLE_SERVICES_JSON" > app/google-services.json
python3 -c "
import json
with open('app/google-services.json') as f: d=json.load(f)
for c in d.get('client',[]): c['client_info']['android_client_info']['package_name']='${PACKAGE_NAME}'
with open('app/google-services.json','w') as f: json.dump(d,f,indent=2)
print('gsj ok')
"

# ── Java kaynak dosyaları ────────────────────────────────────
for JF in MainActivity AppFirebaseMessagingService PlayerActivity ContentAdapter M3uParser; do
  SRC="$GITHUB_WORKSPACE/${JF}.java"
  DST="app/src/main/java/$PKG_PATH/${JF}.java"
  if [ -f "$SRC" ]; then
    sed "s/PACKAGE_PLACEHOLDER/${PACKAGE_NAME}/g" "$SRC" > "$DST"
    if [ "$JF" = "MainActivity" ]; then
      sed -i "s/OWNER_ID_PLACEHOLDER/${OWNER_ID}/g"          "$DST"
      sed -i "s/APP_ID_PLACEHOLDER/${APP_ID}/g"              "$DST"
      sed -i "s/APP_TOPIC_PLACEHOLDER/app_${APP_ID}/g"       "$DST"
      sed -i "s|CONTENT_URL_PLACEHOLDER|${CONTENT_URL:-https://example.com}|g" "$DST"
    fi
    echo "$JF copied"
  fi
done

# ── AndroidManifest ──────────────────────────────────────────
cat > app/src/main/AndroidManifest.xml << MEOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="${APP_NAME}"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:usesCleartextTraffic="true"
        android:hardwareAccelerated="true"
        android:name="androidx.multidex.MultiDexApplication"
        android:theme="@style/AppTheme">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:configChanges="orientation|screenSize|keyboardHidden">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <activity
            android:name=".PlayerActivity"
            android:exported="false"
            android:screenOrientation="sensorLandscape"
            android:configChanges="orientation|screenSize|keyboardHidden"/>
        <service android:name=".AppFirebaseMessagingService" android:exported="false">
            <intent-filter>
                <action android:name="com.google.firebase.MESSAGING_EVENT"/>
            </intent-filter>
        </service>
    </application>
</manifest>
MEOF

# ── Resources ────────────────────────────────────────────────
cat > app/src/main/res/values/colors.xml << CEOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="colorPrimary">#6c63ff</color>
    <color name="colorPrimaryDark">#5a52d5</color>
    <color name="colorAccent">#ff6584</color>
</resources>
CEOF

cat > app/src/main/res/values/strings.xml << SEOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">${APP_NAME}</string>
    <string name="default_notification_channel_id">app_notifications</string>
</resources>
SEOF

cat > app/src/main/res/values/styles.xml << STEOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="AppTheme" parent="android:Theme.Material.Light.NoActionBar">
        <item name="android:colorPrimary">@color/colorPrimary</item>
        <item name="android:colorPrimaryDark">@color/colorPrimaryDark</item>
        <item name="android:colorAccent">@color/colorAccent</item>
        <item name="android:windowBackground">@android:color/black</item>
    </style>
</resources>
STEOF

# ── Icons ────────────────────────────────────────────────────
sudo apt-get install -y -qq imagemagick 2>/dev/null
gen_icon() {
  SZ=$1 DPI=$2
  OUT="app/src/main/res/mipmap-$DPI/ic_launcher.png"
  if [ -f /tmp/icon_source.png ]; then
    convert /tmp/icon_source.png -resize ${SZ}x${SZ} "$OUT"
  else
    convert -size ${SZ}x${SZ} xc:"#6c63ff" -fill white -gravity center \
      -pointsize $((SZ/3)) -annotate 0 "${APP_NAME:0:1}" "$OUT"
  fi
  cp "$OUT" "app/src/main/res/mipmap-$DPI/ic_launcher_round.png"
}
[ -n "$ICON_URL" ] && wget -q "$ICON_URL" -O /tmp/icon_source.png 2>/dev/null || true
gen_icon 72 hdpi; gen_icon 48 mdpi; gen_icon 96 xhdpi
gen_icon 144 xxhdpi; gen_icon 192 xxxhdpi

# ── gradle.properties ────────────────────────────────────────
cat > gradle.properties << GPEOF
android.useAndroidX=true
android.enableJetifier=false
org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=512m
android.nonTransitiveRClass=true
kotlin.stdlib.default.dependency=false
GPEOF

# ── settings.gradle ──────────────────────────────────────────
cat > settings.gradle << SGEOF
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
SGEOF

# ── Root build.gradle ─────────────────────────────────────────
cat > build.gradle << BGEOF
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:7.4.2'
        classpath 'com.google.gms:google-services:4.3.15'
    }
}
BGEOF

# ── App build.gradle ──────────────────────────────────────────
PKG=$PACKAGE_NAME
VC=${VERSION_CODE:-1}
VN=${VERSION_NAME:-1.0}

cat > app/build.gradle << ABEOF
apply plugin: 'com.android.application'
apply plugin: 'com.google.gms.google-services'

android {
    namespace '$PKG'
    compileSdkVersion 34

    defaultConfig {
        applicationId '$PKG'
        minSdkVersion 21
        targetSdkVersion 34
        versionCode $VC
        versionName '$VN'
        multiDexEnabled true
    }

    // Java 8 — desugaring gerekmez, tüm kütüphanelerle uyumlu
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }

    buildTypes {
        release {
            minifyEnabled false
        }
    }

    packagingOptions {
        resources {
            excludes += [
                'META-INF/DEPENDENCIES',
                'META-INF/LICENSE',
                'META-INF/NOTICE',
                'META-INF/*.kotlin_module',
                'META-INF/AL2.0',
                'META-INF/LGPL2.1'
            ]
        }
    }
}

configurations.all {
    resolutionStrategy {
        // Kotlin stdlib tek sürüme sabitle
        force 'org.jetbrains.kotlin:kotlin-stdlib:1.8.22'
        force 'org.jetbrains.kotlin:kotlin-stdlib-common:1.8.22'
        // okio-jvm 3.x dex hatası — 2.x'e sabitle
        force 'com.squareup.okio:okio:2.10.0'
        exclude group: 'org.jetbrains.kotlin', module: 'kotlin-stdlib-jdk7'
        exclude group: 'org.jetbrains.kotlin', module: 'kotlin-stdlib-jdk8'
        // okio-jvm 3.x'i tamamen dışla
        exclude group: 'com.squareup.okio', module: 'okio-jvm'
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

    // ExoPlayer Media3 1.2.1
    implementation 'androidx.media3:media3-exoplayer:1.2.1'
    implementation 'androidx.media3:media3-exoplayer-hls:1.2.1'
    implementation 'androidx.media3:media3-exoplayer-dash:1.2.1'
    implementation 'androidx.media3:media3-exoplayer-rtsp:1.2.1'
    implementation 'androidx.media3:media3-exoplayer-smoothstreaming:1.2.1'
    implementation 'androidx.media3:media3-ui:1.2.1'
    implementation 'androidx.media3:media3-datasource-okhttp:1.2.1'

    // OkHttp 3.x — okio 2.x kullanır, dex sorunu yok
    implementation('com.squareup.okhttp3:okhttp:3.12.13') {
        exclude group: 'com.squareup.okio', module: 'okio-jvm'
    }
    implementation 'com.squareup.okio:okio:2.10.0'
    implementation 'org.jetbrains.kotlin:kotlin-stdlib:1.8.22'
}
ABEOF

# ── Gradle wrapper ───────────────────────────────────────────
mkdir -p gradle/wrapper
cat > gradle/wrapper/gradle-wrapper.properties << GWEOF
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\\://services.gradle.org/distributions/gradle-${GV}-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
GWEOF

# ── Build ────────────────────────────────────────────────────
echo "Starting Gradle build (AGP 7.4.2 / Gradle 7.6.4 / Java 8)..."
"$GRADLE" assembleRelease --no-daemon --no-configuration-cache 2>&1 | tail -50

APK_IN="$WS/app/build/outputs/apk/release/app-release-unsigned.apk"
APK_OUT="/tmp/${PACKAGE_NAME}_v${VC}.apk"
AAB_OUT="/tmp/${PACKAGE_NAME}_v${VC}.aab"

if [ ! -f "$APK_IN" ]; then
  echo "APK not found. Build output:"
  find "$WS/app/build" -name "*.apk" 2>/dev/null || echo "No APK files"
  exit 1
fi

# ── Sign ─────────────────────────────────────────────────────
keytool -genkey -v \
  -keystore /tmp/ks.jks -alias release \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass android -keypass android \
  -dname "CN=Android,OU=Android,O=Android,L=Android,S=Android,C=US" \
  -noprompt 2>/dev/null

"$BUILD_TOOLS_DIR/zipalign" -v 4 "$APK_IN" /tmp/aligned.apk
"$BUILD_TOOLS_DIR/apksigner" sign \
  --ks /tmp/ks.jks --ks-key-alias release \
  --ks-pass pass:android --key-pass pass:android \
  --out "$APK_OUT" /tmp/aligned.apk

# ── AAB ──────────────────────────────────────────────────────
"$GRADLE" bundleRelease --no-daemon --no-configuration-cache 2>&1 | tail -10
AAB_IN="$WS/app/build/outputs/bundle/release/app-release.aab"
[ -f "$AAB_IN" ] && cp "$AAB_IN" "$AAB_OUT" || echo "AAB skipped"

echo "APK_FILE=$APK_OUT" >> $GITHUB_ENV
echo "AAB_FILE=$AAB_OUT" >> $GITHUB_ENV
echo "BUILD DONE: $(du -sh $APK_OUT 2>/dev/null | cut -f1)"
