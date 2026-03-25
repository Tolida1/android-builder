#!/bin/bash
# ============================================================
# build_app.sh — Firebase Entegreli Android Builder (v2.2 - Full & Fixed)
# ============================================================
set -e

echo "=========================================="
echo "  BUILD START: $APP_NAME ($PACKAGE_NAME)"
echo "  Target: $APP_ID | SDK: 34"
echo "=========================================="

# ── 1. ORTAM HAZIRLIĞI ────────────────────────────────────────
echo "Sistem kontrolleri yapılıyor..."
java -version 2>&1 | head -1
gradle --version 2>&1 | grep "Gradle" | head -1

ANDROID_SDK="${ANDROID_HOME:-/usr/local/lib/android/sdk}"
BUILD_TOOLS_DIR=$(ls -d "$ANDROID_SDK/build-tools/"* 2>/dev/null | sort -V | tail -1)

if [ -z "$BUILD_TOOLS_DIR" ]; then
    echo "HATA: Android Build Tools bulunamadı!"
    exit 1
fi

export PATH="$BUILD_TOOLS_DIR:$ANDROID_SDK/platform-tools:$PATH"

# ── 2. DİZİN YAPISI ───────────────────────────────────────────
BUILD_DIR="/tmp/build_${APP_ID}_$$"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

PACKAGE_PATH=$(echo "$PACKAGE_NAME" | tr '.' '/')
mkdir -p app/src/main/java/$PACKAGE_PATH
mkdir -p app/src/main/res/{values,mipmap-hdpi,mipmap-mdpi,mipmap-xhdpi,mipmap-xxhdpi,mipmap-xxxhdpi,layout}

# ── 3. JAVA DOSYALARI (WebView + Firebase) ────────────────────
cat > app/src/main/java/$PACKAGE_PATH/MainActivity.java << JAVA_EOF
package ${PACKAGE_NAME};

import android.app.Activity;
import android.os.Bundle;
import android.webkit.*;
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
    private static final int PERMISSION_CODE = 1001;
    private static final String OWNER_ID = "${OWNER_ID}";
    private static final String APP_ID = "${APP_ID}";
    private static final String URL = "${CONTENT_URL:-https://google.com}";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN, WindowManager.LayoutParams.FLAG_FULLSCREEN);

        webView = new WebView(this);
        setContentView(webView);

        WebSettings s = webView.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setAllowFileAccess(true);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);

        webView.setWebViewClient(new WebViewClient());
        webView.loadUrl(URL);

        checkPermissions();
        initFirebase();
    }

    private void checkPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, new String[]{Manifest.permission.POST_NOTIFICATIONS}, PERMISSION_CODE);
            }
        }
    }

    private void initFirebase() {
        FirebaseMessaging.getInstance().subscribeToTopic("all_users");
        FirebaseMessaging.getInstance().getToken().addOnCompleteListener(task -> {
            if (task.isSuccessful()) saveToken(task.getResult());
        });
    }

    private void saveToken(String token) {
        Map<String, Object> data = new HashMap<>();
        data.put("token", token);
        data.put("lastSeen", System.currentTimeMillis());
        FirebaseFirestore.getInstance().collection("owners").document(OWNER_ID)
            .collection("apps").document(APP_ID).collection("devices")
            .document(token.substring(0, 15)).set(data, SetOptions.merge());
    }

    @Override
    public void onBackPressed() {
        if (webView.canGoBack()) webView.goBack();
        else super.onBackPressed();
    }
}
JAVA_EOF

cat > app/src/main/java/$PACKAGE_PATH/MyFCMService.java << JAVA_EOF
package ${PACKAGE_NAME};
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

public class MyFCMService extends FirebaseMessagingService {
    @Override
    public void onMessageReceived(RemoteMessage message) {
        super.onMessageReceived(message);
    }
}
JAVA_EOF

# ── 4. MANIFEST & RESOURCES ──────────────────────────────────
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
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <service android:name=".MyFCMService" android:exported="false">
            <intent-filter><action android:name="com.google.firebase.MESSAGING_EVENT" /></intent-filter>
        </service>
    </application>
</manifest>
MANIFEST_EOF

echo '<?xml version="1.0" encoding="utf-8"?><resources><string name="app_name">'"${APP_NAME}"'</string></resources>' > app/src/main/res/values/strings.xml

# ── 5. GRADLE CONFIGURATION (KRİTİK HATA DÜZELTMESİ) ──────────
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

    # ==========================================
    # HATA ÇÖZÜMÜ: NATIVE LIBS & RESOURCE MERGE
    # ==========================================
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

# ── 6. GOOGLE SERVICES JSON ──────────────────────────────────
if [ -z "$GOOGLE_SERVICES_JSON" ]; then
    echo "HATA: GOOGLE_SERVICES_JSON boş olamaz!"
    exit 1
fi
echo "$GOOGLE_SERVICES_JSON" > app/google-services.json

# ── 7. BUILD İŞLEMİ ──────────────────────────────────────────
echo "Build başlatılıyor..."
gradle clean assembleRelease --stacktrace

# ── 8. ÇIKTI KONTROLÜ ────────────────────────────────────────
APK_FILE="app/build/outputs/apk/release/app-release-unsigned.apk"
if [ -f "$APK_FILE" ]; then
    echo "------------------------------------------"
    echo " BAŞARILI: $APK_FILE"
    echo "------------------------------------------"
else
    echo "Build başarısız oldu!"
    exit 1
fi
