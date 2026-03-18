# Keep ML Kit classes
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# Keep TensorFlow Lite classes
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# Keep camera classes
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

