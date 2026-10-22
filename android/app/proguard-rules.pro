# Flutter's own embedding is kept by the Flutter Gradle plugin's rules.
# Keep only what reflection reaches; everything else may be stripped.

# flutter_secure_storage is reached through platform channels, which R8
# cannot see as a call graph.
-keep class io.flutter.plugins.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Keep the line table so a crash report stays mappable against the build's
# mapping.txt, but hide the original file names from anyone reading the APK.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
