# DailyValo — R8/ProGuard rules for release builds.

# ---------------------------------------------------------------------------
# flutter_local_notifications
# ---------------------------------------------------------------------------
# The plugin serialises scheduled notifications with Gson and reflects over
# these classes at runtime; R8 cannot see those uses and would strip them.
-keep class com.dexterous.** { *; }
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }

# Gson itself relies on generic signatures and annotations surviving.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-dontwarn sun.misc.**

# ---------------------------------------------------------------------------
# WorkManager
# ---------------------------------------------------------------------------
# Workers are instantiated reflectively by name from the WorkManager database,
# including after a reboot, so their constructors must be kept.
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.Worker { *; }
-keep class * extends androidx.work.ListenableWorker { *; }
-keep class dev.fluttercommunity.workmanager.** { *; }

# ---------------------------------------------------------------------------
# Core library desugaring
# ---------------------------------------------------------------------------
-dontwarn java.lang.invoke.**
-dontwarn **$$ExternalSyntheticLambda*
