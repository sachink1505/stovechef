# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Supabase / GoTrue / PostgREST
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**

# Google Fonts — prevent stripping HTTP client
-keep class com.google.fonts.** { *; }

# OkHttp / okio (used by various plugins)
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**

# Keep annotations
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
