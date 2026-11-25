# ModelLive release-build keep rules.
# WebRTC and the VideoSDK plugin call into each other through JNI (native
# code looks classes and methods up by NAME). If R8 renames or removes them
# in a release build, the app crashes the moment the live stream connects.
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

-keep class live.videosdk.** { *; }
-dontwarn live.videosdk.**

-keep class com.cloudwebrtc.webrtc.** { *; }
-dontwarn com.cloudwebrtc.webrtc.**

-keep class io.flutter.plugins.** { *; }

# Google Play Billing (in_app_purchase)
-keep class com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.**
