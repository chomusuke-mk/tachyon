# ProGuard / R8 rules for Tachyon

# audio_service plugin
-keep class com.ryanheise.audioservice.** { *; }
-keep interface com.ryanheise.audioservice.** { *; }
-keep class com.ryanheise.audio_session.** { *; }

# AndroidX Media & MediaCompat
-keep class androidx.media.** { *; }
-keep class android.support.v4.media.** { *; }
-keep class androidx.core.app.NotificationCompat** { *; }
-keep class androidx.media.app.NotificationCompat** { *; }

# Flutter standard keep rules
-keepattributes SourceFile,LineNumberTable
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Play Core deferred components optional dependency warnings
-dontwarn com.google.android.play.core.**
