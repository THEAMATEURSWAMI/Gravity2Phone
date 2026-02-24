---
description: Build and Distribute the Antigravity Bridge App to your phone
---

This workflow builds the Android APK and uploads it to Firebase App Distribution.

1. Ensure your phone's email is added as a tester in the Firebase Console.
2. Run the build command:
// turbo
3. flutter build apk --debug
4. Upload to Firebase:
// turbo
5. firebase appdistribution:distribute app/build/app/outputs/flutter-apk/app-debug.apk --app 1:304820269242:android:cf6228313dca45d6c5d283 --testers "noless42@gmail.com"
