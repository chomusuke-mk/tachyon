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

# Dart JNI & Pigeon JNI (shared_preferences_android >= 2.5.0)
# Prevents R8 from obfuscating or stripping Kotlin types referenced by string
# descriptor from Dart FFI/JNI (e.g. Continuation -> Lh6; in suspend functions).
-keep class com.github.dart_lang.jni.** { *; }
-keep class kotlin.Metadata { *; }
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.jvm.internal.DefaultConstructorMarker { *; }
-keep interface kotlin.coroutines.Continuation { *; }
-keep interface kotlin.coroutines.CoroutineContext { *; }
-keep class kotlin.coroutines.intrinsics.** { *; }

# Play Core deferred components optional dependency warnings
-dontwarn com.google.android.play.core.**
