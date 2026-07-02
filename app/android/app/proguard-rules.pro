# WARNING: If the release APK crashes on cold start, the likely cause is a missing
# keep rule for a reflective library. Re-introduce keeps incrementally.

# --- Flutter ------------------------------------------
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
# Flutter engine references Play Core for deferred components; this app does
# not bundle Play Core, so silence the missing-class warnings.
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# --- Firebase -----------------------------------------
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Crashlytics - keep all custom Exception classes (so stack traces don't get obfuscated names)
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# --- Health Connect -----------------------------------
-keep class androidx.health.** { *; }
-keep class androidx.health.platform.** { *; }
-keep class androidx.health.connect.** { *; }
-dontwarn androidx.health.**

# --- Google Sign-In (if used) -------------------------
-keep class com.google.android.gms.auth.** { *; }

# --- Play Billing (RevenueCat path) -------------------
-keep class com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.**

# --- Retrofit / OkHttp (if used by any plugin) --------
-dontwarn retrofit2.**
-dontwarn okhttp3.**
-dontwarn okio.**

# --- JSON / Reflection --------------------------------
# Gson is pulled in natively by flutter_local_notifications (persists
# scheduled notifications via RuntimeTypeAdapterFactory): generic signatures
# and TypeToken subclasses must survive R8 or scheduled/boot notifications
# fail to deserialize. App JSON models are Dart-side and need no keeps.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# --- Kotlin metadata ----------------------------------
-keep class kotlin.Metadata { *; }
-keep class kotlin.coroutines.** { *; }
-keep class kotlinx.coroutines.** { *; }

# --- Plugins commonly using reflection ----------------
# mobile_scanner
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-dontwarn com.google.mlkit.**

# image_picker
-keep class io.flutter.plugins.imagepicker.** { *; }

# workmanager 0.9.x — Android package is dev.fluttercommunity.workmanager
# (be.tramckrijte only applies to workmanager < 0.6).
-keep class androidx.work.** { *; }
-keep class dev.fluttercommunity.workmanager.** { *; }

# url_launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# geolocator / location plugins
-keep class com.baseflow.geolocator.** { *; }
-keep class com.lyokone.location.** { *; }

# flutter_local_notifications (Gson rules above are also required)
-keep class com.dexterous.** { *; }

# sqflite_sqlcipher -> net.zetetic:sqlcipher-android. JNI callbacks into these
# classes; stripping/renaming them breaks every encrypted local DB (health,
# journal, workouts, GPS tracks).
-keep class net.zetetic.database.** { *; }
-dontwarn net.zetetic.database.**

# home_widget — background callback dispatcher; the app's own widget providers
# (com.lunaoscar.zvelt.widget.*) are manifest-registered and kept by AGP.
-keep class es.antonborri.home_widget.** { *; }

# --- Generic - keep all Parcelable creators -----------
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator CREATOR;
}

# --- Enum protection ----------------------------------
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
