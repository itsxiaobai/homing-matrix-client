# ProGuard/R8 rules for R8/lightweight build
# Based on Flutter recommended patterns; refined per RING requirements
-dontwarn com.google.android.gms.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# Keep Flutter core and plugin classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Matrix / Vodozemac (E2EE engine)
-keep class org.vodozemac.** { *; }
-keep class net.famedly.** { *; }
-keep class org.matrix.** { *; }
-keepattributes Signature,Exceptions,InnerClasses

# Firebase/Dart engine if used later (payload safe)
-keep class com.google.firebase.** { *; }

# Mobile Scanner (camera)
-keep class io.barcode.** { *; }
-keep class io.github.juliansteenbakker.** { *; }

# Secure Storage
-keep class androidx.security.** { *; }

# Allow optional Google Play Core classes (not provided in runtime)
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.**
