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

## Release

The app is private: for the Fidelia team only.

1. **Create the signing key, once**: `scripts/create-signing-key.sh` makes `~/fidelia-admin-release.jks` (alias `fidelia-admin`) and writes the four secrets to `~/fidelia-admin-github-secrets.txt`. Keep the `.jks` and its password in a password manager: without that exact key, installed copies can never be updated. Check it later with `scripts/check-signing-key.sh`. Never commit a `.jks`, `key.properties` or the secrets file (all git-ignored).
2. **GitHub repository settings** (Settings, Secrets and variables, Actions):
   - Secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
   - Variable: `FIDELIA_API_BASE`, the API's https address (required; the workflow fails if it is unset or not https).
3. **Tag**: `git tag v0.1.0 && git push origin v0.1.0`. The workflow runs `flutter analyze` and `flutter test`, builds the signed APK and the Play bundle, checks the APK signature, and publishes the GitHub Release "Fidelia Admin 0.1.0" with the APK. The version name comes from the tag, the version code from the run number. The bundle is kept as the run artifact `play-bundle-<version>-<run number>`, with the obfuscation symbols.

Local build: `scripts/build-release.sh https://<api host>` (needs `android/key.properties`, see `android/key.properties.example`; without it a release build is left unsigned on purpose).

### Distribution

Through Google Play **internal testing** (upload the `.aab` from the run artifact) or by handing the APK to team members directly. Never publish it: no public store listing, no public link, and keep the repository private.

### First admin

The first admin's password is set on the server, not in the app:

```
python -m app.scripts.set_password +225XXXXXXXXXX
```

Then sign in with that number and the password; the app may ask for a new password if it is temporary.
