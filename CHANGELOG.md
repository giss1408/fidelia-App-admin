# Changelog — Fidelia Admin

What each version of the admin app does, newest first. Versions are git tags
(`vX.Y.Z`); each one builds a signed APK (GitHub Release) and the bundle for
Google Play (internal testing).

## v0.1.0 — 2026-10-22

First version, for the Fidelia team only.

- **Connexion**: sign in with phone number and password; only accounts with
  the admin role get in. The session is kept in the Android Keystore.
- **Changement de mot de passe obligatoire**: an account given a temporary
  password must choose its own before using the app.
- **À traiter**: the lists of accounts waiting for a code or a temporary
  password, with sending by WhatsApp (the message opens ready to send; no
  code or password is shown in the lists or logged).
- **Utilisateurs**: browse and search accounts, and manage them.
- **Compte**: your own account, change your password, sign out.
- Release build: signed APK and Play bundle from a version tag, launcher icon
  with the Admin badge.
