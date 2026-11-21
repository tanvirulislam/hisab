# flutter_local_notifications stores scheduled notifications as JSON (Gson);
# R8 must not rename or strip the model classes it reads back by reflection.
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
