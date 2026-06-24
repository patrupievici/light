# Health Connect pe emulator (Pixel / AVD)

## Cerințe Google

- **minSdk 28+** (Android 9+) — în proiect este setat `minSdk = 28`.
- Pe **API 34+** Health Connect este modul de sistem; pe **API mai mic** trebuie aplicația Health Connect din Play Store.
- Folosește **system image cu Google Play**, nu imagine fără Play (altfel apare „indisponibil” / compatibilitate).

## „App update needed” / „zvelt_app needs to be updated” în Health Connect

Health Connect poate afișa asta când **aplicația Flutter** are `compileSdk` / `targetSdk` prea mici față de modulul HC de pe telefon (Android 15 / Pixel 9). În proiect:

- `compileSdk` este ridicat la **minim 36** (aliniat cu pluginul `health`).
- `targetSdk` este ridicat la **minim 35**.
- Este declarat explicit `androidx.health.connect:connect-client:1.2.0-alpha02`.

După modificare: **dezinstalează** app-ul de pe emulator, apoi `flutter clean` și `flutter run`. Dacă build-ul cere SDK 36, instalează **Android SDK Platform 36** din Android Studio → SDK Manager.

## Dacă vezi eroare pe „Pixel 9” virtual

1. **Device Manager → Create Device** (sau editează AVD):
   - Alege o imagine **Google Play** (icon cu Play), de ex. **Pixel 8 / API 34** sau **API 35 cu Play**.
2. Pornește emulatorul, deschide **Play Store** și:
   - actualizează **Google Play services** / **Android System Intelligence** dacă cere;
   - dacă apare **Health Connect** ca aplicație separată pe API &lt; 34, instaleaz-o.
3. În app: **Home → Open Health**:
   - dacă statusul e **provider update required**, apasă **Instalează / actualizează Health Connect**, apoi **Reîncearcă**.

## Manifest (deja în proiect)

- `<queries>` cu `com.google.android.apps.healthdata`
- `intent-filter` `androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE` pe `MainActivity`
- `activity-alias` `ViewPermissionUsageActivity` (recomandat de documentația Health Connect)

După schimbări majore la manifest, fă **reinstall** pe emulator (uninstall app + `flutter run`).
