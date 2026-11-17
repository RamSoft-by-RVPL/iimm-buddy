# flutter_local_notifications stores scheduled reminders as JSON (Gson).
# Without these rules the release build cannot read them back when they fire.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
# Background checks and the cookie bridge are started by name.
-keep class dev.fluttercommunity.workmanager.** { *; }
-keep class dev.attendance.cookie_bridge.** { *; }
# Firebase push: its background entry points are started by name.
-keep class io.flutter.plugins.firebase.** { *; }
