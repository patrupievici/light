import 'dart:async';
import 'dart:io' show HttpClient;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'l10n/gen/app_localizations.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';
import 'config/api_config.dart' show apiBaseUrl;
import 'config/app_navigator.dart';
import 'config/firebase_options.dart';
import 'config/usda_api_config.dart';
import 'l10n/app_strings.dart';
import 'theme/app_theme.dart';
import 'theme/zvelt_tokens.dart';
import 'theme/zvelt_theme_notifier.dart';
import 'theme/locale_notifier.dart';
import 'services/app_data_cache.dart';
import 'services/fcm_background.dart';
import 'services/moderation_service.dart';
import 'services/secure_db.dart';
import 'services/health_service.dart';
import 'services/location_service.dart';
import 'services/offline_sync_coordinator.dart';
import 'services/push_messaging_service.dart';
import 'services/report_outbox_service.dart';
import 'services/retention_reminder_service.dart';
import 'services/settings_store.dart';
import 'screens/main_screen.dart';
import 'screens/onboarding/onboarding_keys.dart' show kOnboarding2CompletedKey;
import 'screens/onboarding/light_onboarding_flow.dart';
import 'screens/splash_screen.dart';
import 'screens/workouts/workout_tracker_screen.dart';
import 'services/auth_service.dart';
import 'services/workout_draft_store.dart';
import 'services/workout_service.dart';

/// Legacy completion flag for the retired V2 onboarding flow. Kept so users who
/// finished the old flow are not pushed through V3 again. (V2 UI was deleted; the
/// live flow is OnboardingV3.)
const String kOnboardingV2CompletedKey = 'zvelt_onboarding_v2_completed';

/// Wave 8 — background entry point for the Health Connect incremental sync.
/// Runs in an isolate with no UI; keep work scoped to [HealthService] and
/// always return a result so WorkManager doesn't retry-storm on transient
/// failures. `@pragma('vm:entry-point')` is mandatory — without it the
/// Dart tree-shaker drops the symbol in release builds.
@pragma('vm:entry-point')
void healthSyncCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final inserted = await HealthService.instance.incrementalSync();
      debugPrint('[Workmanager] $task done, inserted=$inserted');
      return true;
    } catch (e, st) {
      debugPrint('[Workmanager] $task failed: $e\n$st');
      // Returning true prevents a retry storm. The next periodic tick (~15m)
      // will try again with a fresh state.
      return true;
    }
  });
}

/// Wave 8 — periodic health sync registration. Android-only:
/// `workmanager` on iOS uses BGTaskScheduler which requires extra
/// `Info.plist` permitted-identifiers entries + Xcode capabilities; for the
/// v1.0 release iOS background sync is intentionally deferred to HealthKit
/// observer queries (separate path). On unsupported platforms this is a
/// no-op.
Future<void> _registerHealthBackgroundSync() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await Workmanager().initialize(healthSyncCallbackDispatcher);
    await Workmanager().registerPeriodicTask(
      'health_incremental_sync',
      'health_incremental_sync',
      frequency: const Duration(minutes: 15),
      // Reading Health Connect is an on-device operation — it needs no network.
      // Requiring connectivity needlessly blocked the sync (and ColorOS/Oppo
      // already defers background work aggressively). NotRequired lets it run.
      constraints: Constraints(networkType: NetworkType.notRequired),
      // update: re-register existing installs with the relaxed constraint
      // WITHOUT cancelling the in-flight schedule. (replace would cancel +
      // restart the 15-min clock on every cold start, so a user who opens the
      // app more than once per 15 min would starve the background sync.)
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  } catch (e, st) {
    debugPrint('[bootstrap] Workmanager registration failed: $e\n$st');
  }
}

/// Fire-and-forget GET to Render at boot. Render free tier sleeps after
/// 15 min idle and takes ~30-60s to wake. By the time the user navigates
/// to login, the dyno is already warm and the auth call returns in <300ms
/// instead of timing out. Any HTTP response (even 404) wakes the dyno; we
/// pin a long timeout so it doesn't get cancelled on slow networks.
Future<void> _warmupBackend() async {
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final req = await client
        .getUrl(Uri.parse('$apiBaseUrl/health'))
        .timeout(const Duration(seconds: 75));
    final resp = await req.close().timeout(const Duration(seconds: 75));
    await resp.drain<void>();
    client.close();
    debugPrint('[bootstrap] warmup ping: ${resp.statusCode}');
  } catch (e) {
    // Expected on cold start / no network — auth flow has its own 75s
    // timeout so login still works even if this fails.
    debugPrint('[bootstrap] warmup ping skipped: $e');
  }
}

Future<void> _configureLocalTimezone() async {
  tzdata.initializeTimeZones();
  try {
    final info = await FlutterTimezone.getLocalTimezone().timeout(
      const Duration(seconds: 8),
      onTimeout: () => throw TimeoutException('FlutterTimezone'),
    );
    tz.setLocalLocation(tz.getLocation(info.identifier));
  } catch (e) {
    debugPrint('[bootstrap] _configureLocalTimezone fallback to UTC: $e');
    tz.setLocalLocation(tz.UTC);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // P0.6 — Crashlytics. Initialize Firebase + wire the framework / async
  // error handlers BEFORE the first `runApp` so cold-start crashes are
  // captured. Disabled in debug to avoid polluting the Firebase console
  // with dev-time exceptions. Firebase init is idempotent — the lazy
  // `Firebase.initializeApp` calls in PushMessagingService / fcm_background
  // detect existing apps and short-circuit.
  if (!kIsWeb && DefaultFirebaseOptions.isConfigured) {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode);
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (e, st) {
      debugPrint('[bootstrap] Crashlytics init failed: $e\n$st');
    }
  }
  try {
    await dotenv.load(fileName: 'assets/dotenv');
    UsdaApiConfig.syncFromDotenv();
  } catch (e, st) {
    debugPrint('USDA dotenv load skipped: $e\n$st');
  }
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: ZveltTokens.bg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  if (!kIsWeb &&
      DefaultFirebaseOptions.fcmEnabled &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
  // Nu blocăm primul frame: initializeTimeZones() e sincron și greu; IndexedStack pornea toate taburile odată.
  runApp(const _AppBootstrap());
}

/// Încarcă timezone + local notifications după primul frame ca să evite ANR / „Skipped frames” la cold start.
class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap>
    with WidgetsBindingObserver {
  bool _ready = false;
  Object? _error;

  /// Offline-first — set true once [OfflineSyncCoordinator.start] has been
  /// kicked off, so the lifecycle observer only flushes after the coordinator
  /// is wired (and we don't re-trigger a flush on the first resume that
  /// precedes bootstrap completing).
  bool _offlineSyncStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Offline-first — when the app returns to the foreground, attempt to drain
    // any sets logged offline. Fire-and-forget + guarded so a teardown/error
    // can never bubble into the framework's lifecycle dispatch. Only after the
    // coordinator has been started during bootstrap.
    if (state == AppLifecycleState.resumed && _offlineSyncStarted) {
      unawaited(
        OfflineSyncCoordinator.instance
            .refreshPending(flush: true)
            .catchError((Object e, StackTrace st) {
          debugPrint('[bootstrap] offline sync resume flush failed: $e\n$st');
        }),
      );
    }
  }

  Future<void> _prepare() async {
    try {
      // Yield to the engine so the first frame renders before heavy init.
      // Two 16ms delays ensure the first frame is fully painted.
      await Future<void>.delayed(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 16));
      // Wake Render free-tier dyno while the user navigates to login —
      // fire-and-forget, ~30-60s cold start happens off the critical path.
      unawaited(_warmupBackend());
      await ZveltThemeNotifier.init();
      await LocaleNotifier.init();
      await UnitsNotifier.init();
      await AppPreferencesNotifier.init();
      await _configureLocalTimezone();
      try {
        await RetentionReminderService.instance.ensureInitialized().timeout(
          const Duration(seconds: 12),
          onTimeout: () {
            debugPrint(
                '[bootstrap] RetentionReminderService.ensureInitialized timeout — continue');
          },
        );
      } catch (e, st) {
        debugPrint('[bootstrap] RetentionReminder init: $e\n$st');
      }
      // Wave 8 — register the WorkManager periodic task for Health Connect
      // incremental sync. Fire-and-forget; failures are logged but do not
      // block bootstrap.
      unawaited(_registerHealthBackgroundSync());
      // Wave 22 P0.2 — best-effort drain of any reports queued while the
      // moderation backend was offline. Fire-and-forget; the outbox is
      // also drained whenever the user opens BlockedUsersScreen.
      unawaited(ReportOutboxService.shared().drain());
      // Offline-first — start the connectivity bridge that auto-flushes the
      // offline set queue on reconnect. Runs AFTER auth state is loadable (the
      // queue keys off the stored user id and AuthService is already warmed by
      // the warmup/bootstrap calls above). Fire-and-forget so it never blocks
      // first frame; start() is idempotent and the queue defers flushes that
      // fail (offline / no token) for the next reconnect or app resume.
      _offlineSyncStarted = true;
      unawaited(
        OfflineSyncCoordinator.instance
            .start()
            .catchError((Object e, StackTrace st) {
          debugPrint(
              '[bootstrap] OfflineSyncCoordinator.start failed: $e\n$st');
        }),
      );
      if (mounted) setState(() => _ready = true);
    } catch (e, st) {
      debugPrint('[bootstrap] $e\n$st');
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.themeData,
        home: Scaffold(
          backgroundColor: ZveltTokens.bg,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Startup failed: $_error',
                textAlign: TextAlign.center,
                style: TextStyle(color: ZveltTokens.text2),
              ),
            ),
          ),
        ),
      );
    }
    if (!_ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.themeData,
        home: Scaffold(
          backgroundColor: ZveltTokens.bg,
          body: const Center(
            child: CircularProgressIndicator(color: ZveltTokens.info),
          ),
        ),
      );
    }
    return const ZveltApp();
  }
}

class ZveltApp extends StatelessWidget {
  const ZveltApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ZveltThemeNotifier.mode,
      builder: (context, themeMode, _) {
        // Drive the runtime token brightness from the resolved theme mode
        // (system → current platform brightness). Every ZveltTokens neutral +
        // ZType style reads this flag; the rebuild below repaints the tree.
        final platformDark = WidgetsBinding.instance.platformDispatcher
                .platformBrightness ==
            Brightness.dark;
        ZveltTokens.isDark = switch (themeMode) {
          ThemeMode.dark => true,
          ThemeMode.light => false,
          ThemeMode.system => platformDark,
        };
        return ValueListenableBuilder<int>(
        valueListenable: AppPreferencesNotifier.accent,
        builder: (context, accentValue, _) => ValueListenableBuilder<bool>(
          valueListenable: AppPreferencesNotifier.reduceMotion,
          builder: (context, reduceMotion, _) =>
              ValueListenableBuilder<Locale?>(
            valueListenable: LocaleNotifier.locale,
            builder: (context, appLocale, _) {
              final accent = Color(accentValue);
              return MaterialApp(
                navigatorKey: AppNavigator.key,
                title: AppStrings.appName,
                debugShowCheckedModeBanner: false,
                // UI-language picker wiring (P2). `locale` follows the user's
                // saved choice (null = follow system); resolution always lands
                // on a locale the app can render, with English as the fallback.
                locale: appLocale,
                // i18n scaffold — generated AppLocalizations delegate plus the
                // Flutter Material/Cupertino/Widgets delegates. supportedLocales
                // comes from the generated set (en + ro skeleton); keys missing
                // in ro fall back to the English template, so the UI stays fully
                // rendered while translation lands incrementally. Only the pilot
                // (settings/language_screen.dart) consumes AppLocalizations so
                // far — full migration is incremental.
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                localeResolutionCallback: LocaleNotifier.localeResolution,
                theme: AppTheme.lightThemeData.copyWith(
                  colorScheme: AppTheme.lightThemeData.colorScheme
                      .copyWith(primary: accent, secondary: accent),
                ),
                darkTheme: AppTheme.themeData.copyWith(
                  colorScheme: AppTheme.themeData.colorScheme
                      .copyWith(primary: accent, secondary: accent),
                ),
                themeMode: themeMode,
                // Safety net: cap the system font scale so an extra-large device font
                // (common on Samsung) can't blow up dense layouts. Moderate scaling is
                // still respected for accessibility.
                builder: (context, child) {
                  // Resolve the ACTIVE brightness (light/dark/system, incl. live
                  // OS changes) and drive the runtime tokens from it. ZveltTokens
                  // widgets read static getters, not Theme.of, so they don't
                  // rebuild on a theme flip on their own — keying the subtree by
                  // brightness forces a full repaint when the mode actually
                  // changes (a rare action; cost is the nav stack resetting).
                  ZveltTokens.isDark =
                      Theme.of(context).brightness == Brightness.dark;
                  final mq = MediaQuery.of(context);
                  return KeyedSubtree(
                    key: ValueKey<bool>(ZveltTokens.isDark),
                    child: MediaQuery(
                      data: mq.copyWith(
                        textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3),
                        disableAnimations: mq.disableAnimations || reduceMotion,
                      ),
                      child: child ?? const SizedBox.shrink(),
                    ),
                  );
                },
                home: const AuthGate(),
              );
            },
          ),
        ),
        );
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

enum _ResumeChoice { resume, discard, later }

class _AuthGateState extends State<AuthGate> {
  final AuthService _auth = AuthService();

  /// După Welcome → Login. Incrementează sufixul (v3, v4…) când vrei să vezi din nou Welcome pe dispozitive care au deja flag-ul setat.

  /// Pointer older than this is silently discarded (server-side cancel) on
  /// app start instead of prompting — the user has likely moved on. P1.11.
  static const Duration _kActiveWorkoutMaxAge = Duration(hours: 8);

  /// "Later" suppresses the resume prompt for the rest of this process.
  bool _resumePromptedThisSession = false;
  bool _hasToken = false;
  String _userId = ''; // folosit pentru chei per-user la onboarding
  bool _onboardingDone = false;
  bool _loading = true;

  /// Cheie per user ca conturile noi să vadă onboarding. Dacă userId lipsește folosim '_guest'.
  String _key(String base) => '${base}_${_userId.isEmpty ? 'guest' : _userId}';

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final hasToken = await _auth.hasValidToken();
    final prefs = await SharedPreferences.getInstance();
    bool onboardingDone = false;
    String userId = '';
    if (hasToken) {
      // getCurrentUserId() făcea refresh HTTP fără timeout → blocare minute dacă backend-ul e oprit.
      userId = await _auth.getStoredUserId() ?? '';
      _userId = userId;
      // NOTE: do NOT trigger another refresh here — hasValidToken() above
      // already refreshed and cached a fresh access token. A second
      // getAccessToken() raced the single-use refresh token and tripped the
      // backend's reuse-detection, logging the user out on cold start.
      // V3 is the live flow (Razvan's 28-screen redesign); users who already
      // completed the old V2 flow are NOT forced through it again.
      onboardingDone =
          (prefs.getBool(_key(kOnboarding2CompletedKey)) ?? false) ||
              (prefs.getBool(_key('onboarding_v3_completed')) ?? false) ||
              (prefs.getBool(_key(kOnboardingV2CompletedKey)) ?? false);
    }
    if (!mounted) return;
    setState(() {
      _hasToken = hasToken;
      _onboardingDone = onboardingDone;
      _loading = false;
    });
  }

  /// QA P1.11 — if the previous session left a workout open (force-kill /
  /// crash), surface a dialog so the user can resume, discard, or defer.
  /// Auto-discards anything older than [_kActiveWorkoutMaxAge].
  Future<void> _maybePromptResumeWorkout() async {
    if (_resumePromptedThisSession) return;
    final ptr = await WorkoutService.readActiveWorkoutPointer();
    if (ptr == null) return;
    final age = DateTime.now().difference(ptr.startedAt);
    if (age.isNegative || age > _kActiveWorkoutMaxAge) {
      // Auto-discard ONLY stale drafts with no logged sets. A draft with
      // real sets is training data — silently DELETE-ing it (the old
      // behavior) erased a full evening session if the user forgot to tap
      // Complete and reopened the app the next morning. With sets present
      // we fall through to the resume/discard prompt regardless of age.
      var hasLoggedSets = false;
      final draft = await WorkoutDraftStore().load();
      if (draft != null && draft.workoutId == ptr.workoutId) {
        hasLoggedSets = draft.setsLogged > 0;
      } else {
        // No local snapshot (tracker-started workouts don't save one) —
        // ask the server. If unreachable, do nothing this launch: the
        // DELETE would fail offline anyway, and the pointer gets
        // re-evaluated on the next start.
        try {
          final w = await WorkoutService().getWorkout(ptr.workoutId);
          hasLoggedSets = w.exercises.any((e) => e.sets.isNotEmpty);
        } catch (_) {
          return;
        }
      }
      if (!hasLoggedSets) {
        debugPrint(
            '[resume-workout] pointer too old (${age.inHours}h), no logged sets — discarding silently');
        await WorkoutService().discardWorkout(ptr.workoutId);
        return;
      }
      debugPrint(
          '[resume-workout] pointer old (${age.inHours}h) but has logged sets — prompting');
    }
    if (!mounted) return;
    _resumePromptedThisSession = true;
    final choice = await showDialog<_ResumeChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => AlertDialog(
        backgroundColor: ZveltTokens.surface,
        title: const Text('Resume your workout?'),
        content: Text(
          'You started a workout ${_formatElapsed(age)} ago that didn\'t finish.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(_ResumeChoice.later),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(_ResumeChoice.discard),
            child: const Text('Discard',
                style: TextStyle(color: ZveltTokens.error)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dCtx).pop(_ResumeChoice.resume),
            child: const Text('Resume'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case _ResumeChoice.resume:
        AppNavigator.key.currentState?.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => WorkoutTrackerScreen(workoutId: ptr.workoutId),
          ),
        );
        break;
      case _ResumeChoice.discard:
        await WorkoutService().discardWorkout(ptr.workoutId);
        break;
      case _ResumeChoice.later:
      case null:
        // Pointer stays in prefs — we just don't re-prompt this session.
        break;
    }
  }

  static String _formatElapsed(Duration d) {
    if (d.inMinutes < 1) return 'less than a minute';
    if (d.inHours < 1) return '${d.inMinutes} min';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      // Brief §6.1 — the launch wait IS the splash.
      return const SplashScreen();
    }

    if (_hasToken && _onboardingDone) {
      // Once we're past auth + onboarding, surface the resume-workout dialog
      // on top of MainScreen (post-frame so navigator + dialog have a host).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybePromptResumeWorkout();
      });
      return MainScreen(
        // Keyed by user so switching accounts (Settings → Sign in) fully
        // remounts the shell instead of showing the previous user's tabs.
        key: ValueKey('main_$_userId'),
        onSessionChanged: () async {
          // Same per-user cache hygiene as logout, then re-read the session so
          // the new userId/onboarding flags drive a fresh (re-keyed) MainScreen.
          try {
            await AppDataCache.instance.clearSessionCaches();
          } catch (_) {}
          try {
            await ModerationService.clearLocalCache();
          } catch (_) {}
          // Wipe device-global encrypted stores (progress photos, journal,
          // health, stories, tracking) so the new account can't see the
          // previous user's data.
          try {
            await SecureDb.instance.wipeUserData();
          } catch (_) {}
          // Active-workout pointer + draft are global keys — clear them so the
          // next account isn't prompted to resume the previous user's workout.
          try {
            await WorkoutService.clearActiveWorkoutPointer();
            await WorkoutDraftStore().clear();
          } catch (_) {}
          await _checkAuth();
        },
        onLogout: () async {
          // Drop any lingering snackbar (e.g. the race "You're in: …" toast)
          // so it doesn't carry over onto the logged-out screen.
          ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
          // Local-first sign-out: wipe tokens + flip the UI IMMEDIATELY.
          // Service teardown happens after, so a slow stop / dead network
          // can't make the first tap look like it did nothing (the "had to
          // tap Log out twice" bug). AuthService.logout() is fast now — the
          // server-side revoke is fire-and-forget inside it.
          //
          // Unregister the push token FIRST, while the JWT is still valid — once
          // _auth.logout() wipes tokens, stopOnLogout() can't authenticate the
          // DELETE /me/push-token and the device keeps getting the old account's
          // DM pushes.
          try {
            await PushMessagingService.instance.stopOnLogout();
          } catch (_) {}
          await _auth.logout();
          if (mounted) {
            setState(() {
              _hasToken = false;
              _onboardingDone = false;
              _loading = false;
            });
          }
          // Teardown of everything still running / holding user state —
          // each step guarded so one failure can't break the others.
          try {
            LocationService.instance.stopTracking();
          } catch (_) {}
          try {
            await RetentionReminderService.instance.cancelAll();
          } catch (_) {}
          // Per-user local caches — without this the next account on the
          // same device sees the previous user's /me, training profile and
          // block list.
          try {
            await AppDataCache.instance.clearSessionCaches();
          } catch (_) {}
          try {
            await ModerationService.clearLocalCache();
          } catch (_) {}
          // Device-global encrypted stores (progress photos, journal, health,
          // stories, tracking) — without this the next account on the device
          // sees the previous user's private data.
          try {
            await SecureDb.instance.wipeUserData();
          } catch (_) {}
          // Active-workout pointer + draft are global keys — clear them so the
          // next account isn't prompted to resume the previous user's workout.
          try {
            await WorkoutService.clearActiveWorkoutPointer();
            await WorkoutDraftStore().clear();
          } catch (_) {}
        },
      );
    }
    // No token, OR token-but-onboarding-incomplete → the new unified onboarding,
    // which OWNS auth (ScrAuth at screen 4). New users start at the splash and
    // sign in/up INSIDE the flow; a user who already has a token resumes at
    // personalization. A returning user who logs in but already onboarded skips
    // straight into the app (ScrAuth → OnbScreenArgs.complete → onComplete).
    return LightOnboardingFlow(
      completionKey: _key(kOnboarding2CompletedKey),
      startAuthenticated: _hasToken,
      onComplete: () {
        if (mounted) _checkAuth();
      },
    );
  }
}
