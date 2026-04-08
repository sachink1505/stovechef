# App Icons

Add the following PNG files to this directory before running the icon/splash generators:

| File | Size | Purpose |
|------|------|---------|
| `app_icon.png` | 1024×1024 | Full app icon (used as Android legacy icon and iOS icon) |
| `app_icon_foreground.png` | 1024×1024 | Adaptive icon foreground layer (Android 8+). Use a white cooking pot centered with ~66% safe zone padding. Background colour is `#E85D2A` (burnt orange). |
| `splash_logo.png` | 400×400 (min) | Centred logo shown on the native splash screen. White/transparent background. |

After adding the files, run:

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```
