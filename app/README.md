# Zvelt App (Flutter)

Minimal Flutter app: login/signup + main page with buttons (Workouts, Exercises, Profile, Ranks, Log out).

## Run

```bash
cd app
flutter pub get
flutter run
```

- **Chrome:** `flutter run -d chrome` — backend at `http://localhost:3000`
- **Android emulator:** Backend must be reachable. Use `http://10.0.2.2:3000` (emulator’s alias for host). Example:
  ```bash
  flutter run -d <device> --dart-define=API_BASE_URL=http://10.0.2.2:3000
  ```
- **Physical device on same WiFi:** Use your PC’s IP, e.g. `http://192.168.1.x:3000`.

## Backend

Start the backend first (see project root `README.md`). Default API base: `http://localhost:3000`.
