# Android release signing — one-time setup

Release builds **fail on purpose** until real signing is configured (no silent
debug-signed "release" AABs — Play rejects them).

## 1. Create the upload keystore (once, keep it FOREVER)

```
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 \
        -validity 10000 -alias upload
```

Store `upload-keystore.jks` somewhere safe **outside git** (e.g.
`app/android/upload-keystore.jks` — it is gitignored). **Back it up** (password
manager + offline copy): losing it means a Play support process to reset the
upload key.

## 2. Create `app/android/key.properties` (gitignored — never commit)

```
storeFile=../upload-keystore.jks
storePassword=<your store password>
keyAlias=upload
keyPassword=<your key password>
```

`storeFile` is resolved relative to `android/app/`, so `../upload-keystore.jks`
points at `android/upload-keystore.jks`.

## 3. Build

```
flutter build appbundle --release
```

Play App Signing: on first upload, Play Console generates the *app signing
key*; the keystore above is only your *upload key*. If it ever leaks, reset it
from Play Console → Setup → App integrity.

## Never commit
`key.properties`, `*.jks`, `*.keystore` — all gitignored in
`app/android/.gitignore`.
