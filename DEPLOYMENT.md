# StoveChef — Deployment Guide

## Table of Contents
1. [Pre-deployment checklist](#1-pre-deployment-checklist)
2. [Supabase — production setup](#2-supabase--production-setup)
3. [Build the release binaries](#3-build-the-release-binaries)
4. [Android — Google Play Store](#4-android--google-play-store)
5. [iOS — Apple App Store](#5-ios--apple-app-store)
6. [Post-launch](#6-post-launch)

---

## 1. Pre-deployment checklist

Before building, confirm:

- [ ] Supabase project is on the **Pro** plan (or Free plan limits are acceptable)
- [ ] All SQL migrations have been applied on the production Supabase project
- [ ] Row-Level Security (RLS) policies are enabled on all tables
- [ ] Gemini API key has billing enabled (free quota exhausts quickly in production)
- [ ] `DAILY_RECIPE_LIMIT` is configured to the desired value (default: 5)
- [ ] App version in `pubspec.yaml` is bumped (`version: x.y.z+buildNumber`)
- [ ] App icon PNGs are in `assets/icon/` and generators have been run:
  ```bash
  dart run flutter_launcher_icons
  dart run flutter_native_splash:create
  ```
- [ ] Tested on a physical Android device and iOS simulator

---

## 2. Supabase — production setup

### 2a. Create a production project

1. Go to [supabase.com/dashboard](https://supabase.com/dashboard) → **New project**
2. Choose a region close to your primary users (e.g. `ap-south-1` for India)
3. Set a strong database password and store it in a password manager

### 2b. Apply migrations

Run your SQL migration files against the production project:

```bash
# Using the Supabase CLI (install via: brew install supabase/tap/supabase)
supabase db push --db-url "postgresql://postgres:<password>@db.<ref>.supabase.co:5432/postgres"
```

Or paste each migration file manually in the Supabase dashboard under **SQL Editor**.

### 2c. Enable Row-Level Security

For every table (`profiles`, `recipes`, `recipe_steps`, etc.):

1. Dashboard → **Table Editor** → select table → **RLS** tab
2. Enable RLS and verify policies allow:
   - Users to read/write only their own rows
   - Platform recipes to be readable by all authenticated users

### 2d. Configure Auth

1. Dashboard → **Authentication → Providers** → enable **Email**
2. Under **Email** settings:
   - Enable **Confirm email** (OTP flow)
   - Set OTP expiry to **600 seconds** (10 min)
   - Set OTP length to **6** digits (or 4 if your UI shows 4 boxes — match your UI)
3. Under **Auth → URL Configuration**, add your app's deep-link scheme:
   - Site URL: `stovechef://`
   - Redirect URLs: `stovechef://auth/callback`

### 2e. Upgrade plan (if needed)

The **Free plan** limits:
- 500 MB database storage
- 2 GB bandwidth/month
- Pauses after 1 week of inactivity

For a production app, upgrade to **Pro ($25/month)** to avoid pauses and get higher limits.

### 2f. Get production credentials

Dashboard → **Settings → API**:
- **Project URL** → `SUPABASE_URL`
- **anon / public key** → `SUPABASE_ANON_KEY`

Store these securely. Never commit them to git.

---

## 3. Build the release binaries

### Set environment variables

```bash
export SUPABASE_URL=https://xxxxxxxxxxxx.supabase.co
export SUPABASE_ANON_KEY=eyJ...
export GEMINI_API_KEY=AIzaSy...
```

Or source from a local `.env` file (never commit this file):

```bash
set -a && source .env && set +a
```

### Run the build script

```bash
./build.sh              # builds both APK and AAB
./build.sh --aab-only   # Play Store upload only
./build.sh --apk-only   # direct install / testing only
```

Output locations:
| Artifact | Path |
|---|---|
| APK (direct install) | `build/app/outputs/flutter-apk/app-release.apk` |
| AAB (Play Store) | `build/app/outputs/bundle/release/app-release.aab` |

---

## 4. Android — Google Play Store

### 4a. Set up a Google Play Developer account

1. Go to [play.google.com/console](https://play.google.com/console)
2. Pay the one-time $25 registration fee
3. Complete identity verification (can take 24–48 hours)

### 4b. Sign the release build

Google Play requires a signed AAB. Flutter's debug key is not accepted.

**Generate a keystore** (do this once, keep it safe forever):

```bash
keytool -genkey -v \
  -keystore ~/stovechef-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias stovechef
```

**Create `android/key.properties`** (do NOT commit this file):

```properties
storePassword=<keystore password>
keyPassword=<key password>
keyAlias=stovechef
storeFile=<absolute path to stovechef-release.jks>
```

**Update `android/app/build.gradle.kts`** to read the signing config:

```kotlin
import java.util.Properties
import java.io.FileInputStream

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties().apply {
    if (keyPropertiesFile.exists()) load(FileInputStream(keyPropertiesFile))
}

android {
    signingConfigs {
        create("release") {
            keyAlias = keyProperties["keyAlias"] as String
            keyPassword = keyProperties["keyPassword"] as String
            storeFile = file(keyProperties["storeFile"] as String)
            storePassword = keyProperties["storePassword"] as String
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

Add `key.properties` and `*.jks` to `.gitignore`.

### 4c. Create the app listing

1. Play Console → **Create app**
2. Fill in:
   - App name: **StoveChef**
   - Default language: English
   - App or game: App
   - Free or paid: Free
3. Complete the **Store listing**:
   - Short description (80 chars): e.g. *Turn YouTube cooking videos into step-by-step guided recipes*
   - Full description (4000 chars): describe the app flow
   - Screenshots: minimum 2 phone screenshots (required)
   - Feature graphic: 1024×500 px banner
   - App icon: 512×512 px PNG (high-res, separate from the launcher icon)
4. Complete **Content rating** questionnaire
5. Complete **App content** declarations (data safety, target audience)

### 4d. Upload the AAB

1. Play Console → your app → **Release → Production → Create new release**
2. Click **Upload** → select `build/app/outputs/bundle/release/app-release.aab`
3. Add release notes
4. Click **Review release** then **Start rollout to Production**

For initial testing, use **Internal testing** track first (instant publishing, up to 100 testers).

---

## 5. iOS — Apple App Store

### 5a. Set up an Apple Developer account

1. Go to [developer.apple.com](https://developer.apple.com) → enroll in the **Apple Developer Program**
2. Pay $99/year
3. Enrollment review can take up to 48 hours

### 5b. Configure the project in Xcode

1. Open `ios/Runner.xcworkspace` in Xcode (**not** `.xcodeproj`)
2. Select the **Runner** target → **Signing & Capabilities**
3. Set **Team** to your Apple Developer team
4. Set **Bundle Identifier** to match your App Store Connect app (e.g. `com.stovechef.app`)
5. Ensure **Automatically manage signing** is checked

### 5c. Create the app in App Store Connect

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **My Apps → +**
2. Fill in:
   - Platform: iOS
   - Name: **StoveChef**
   - Primary language: English
   - Bundle ID: must match Xcode (e.g. `com.stovechef.app`)
   - SKU: any unique internal identifier (e.g. `stovechef-v1`)
3. Complete **App Information**, **Pricing**, and **App Privacy** sections
4. Add **Screenshots** (required sizes: 6.9", 6.5", 5.5" iPhone; 12.9" iPad if targeting iPad)

### 5d. Build and archive in Xcode

You must build iOS from a Mac with Xcode installed. The `build.sh` script does not handle iOS builds — use Xcode directly.

1. Set the scheme to **Runner** and destination to **Any iOS Device (arm64)**
2. Set environment variables in the scheme:
   - Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables
   - Add `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GEMINI_API_KEY`
   - For release builds, use **Build Pre-Actions** or a `Config.xcconfig` file instead
3. Menu: **Product → Archive**
4. Xcode Organizer opens automatically when archiving completes

### 5e. Upload to App Store Connect

1. In Xcode Organizer, select the archive → **Distribute App**
2. Choose **App Store Connect → Upload**
3. Follow the prompts (keep default options for most steps)
4. After upload (5–10 minutes), the build appears in App Store Connect under **TestFlight**

### 5f. Submit for review

1. App Store Connect → your app → **+ Version** → set version number
2. Select the uploaded build
3. Fill in **What's New in This Version**
4. Click **Submit for Review**
5. Review typically takes 24–48 hours for new apps

### 5g. Passing iOS review — common rejections to avoid

- Ensure **NSUserNotificationUsageDescription** is set in `Info.plist` (already done)
- The app must work without requiring sign-in for basic browsing — or clearly explain why sign-in is needed (recipes are user-specific, so this is acceptable)
- Do not reference competitor platforms (Android, Google Play) in the app copy
- Ensure all external links (YouTube, Supabase) load correctly in the reviewer's environment

---

## 6. Post-launch

### Monitor errors

- Supabase Dashboard → **Logs** to watch API errors and slow queries
- Add [Sentry](https://sentry.io) for Flutter crash reporting: `flutter pub add sentry_flutter`

### Update the daily recipe limit

The limit is configurable via `--dart-define=DAILY_RECIPE_LIMIT=10` — no code change needed. For a server-side override without a rebuild, store the limit in a Supabase config table and fetch it on app start.

### Bump the version before each release

In `pubspec.yaml`:

```yaml
version: 1.1.0+2   # name+buildNumber
```

The build number must be strictly incremented for each Play Store / App Store submission.
