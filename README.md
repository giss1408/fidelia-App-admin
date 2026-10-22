# Fidelia Admin

Private Android app (Flutter, Riverpod, http) for the Fidelia team. Sign in with phone and password (admin role), send WhatsApp codes and temporary passwords, manage accounts. It reuses the core of Fidelia Pro (`ApiClient`, `Env`, `TokenStore`, theme).

## Run against the test API

```
flutter pub get
flutter run --dart-define=FIDELIA_API_BASE=https://<test api host>
```

Local backend from the Android emulator: `--dart-define=FIDELIA_API_BASE=http://10.0.2.2:8000` (debug only; release builds require https).

## Checks

```
flutter analyze
flutter test
flutter build apk --debug --dart-define=FIDELIA_API_BASE=https://<test api host>
```

## Release signing

Copy `android/key.properties.example` to `android/key.properties` (git-ignored, as are `*.jks`). Without it a release build is left unsigned on purpose.
