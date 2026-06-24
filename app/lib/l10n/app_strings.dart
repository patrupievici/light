/// App copy in English. Replace with Localizations when adding language picker.
class AppStrings {
  AppStrings._();

  // — Auth / Login
  static const String appName = 'ZVELT';
  static const String appTagline = 'Fitness • Strength';
  static const String email = 'Email';
  static const String emailHint = 'you@example.com';
  static const String password = 'Password';
  static const String passwordHintLogin = 'Your password';
  static const String passwordHintSignup = 'Min. 8 characters';
  static const String signIn = 'Sign In';
  static const String signUp = 'Sign Up';
  static const String continueWithGoogle = 'Continue with Google';
  static const String noAccount = "Don't have an account? Sign up";
  static const String haveAccount = 'Already have an account? Sign in';
  static const String enterEmail = 'Enter email';
  static const String invalidEmail = 'Invalid email';
  static const String enterPassword = 'Enter password';
  static const String minPassword = 'At least 8 characters';
  static const String googleTokenError = 'Could not get Google sign-in token';

  // — Main / Home
  static const String home = 'Home';
  static const String chooseAction = 'Choose an action';
  static const String workouts = 'Workouts';
  static const String exercises = 'Exercises';
  static const String profile = 'Profile';
  static const String ranksLeaderboard = 'Ranks / Leaderboard';
  static const String nutrition = 'Nutrition';
  static const String social = 'Social';
  static const String rank = 'Rank';
  static const String logOut = 'Log out';
  static const String comingSoon = 'coming soon';

  // — Workouts tab & tracker
  static const String newWorkout = 'New workout';
  static const String suggestedForYou = 'Suggested for you';
  static const String startSuggestedWorkout = 'Start suggested workout';
  static const String noSuggestionAvailable = 'No plan available yet. Finish onboarding or pull to refresh.';
  static const String noWorkoutsYet = 'No workouts yet';
  static const String tapToStartTracking = 'Tap New workout or start a suggested plan below.';
  static const String logSet = 'Log set';
  static const String targetReps = 'Target reps';
  static const String setPending = 'Pending';
  static const String addExercise = 'Add exercise';
  static const String completeWorkout = 'Complete workout';
  static const String workoutComplete = 'Workout complete!';
  static const String discardWorkout = 'Discard workout?';
  static const String progressNotSaved = 'Progress will not be saved.';
  static const String retry = 'Retry';
  static const String done = 'Done';

  // — Onboarding concept (FIG 5–7)
  static const String continueCta = 'Continue';
  static const String concept1Title = 'Ranking by muscle group';
  static const String concept1Message =
      'Each muscle group has its own rank. The more you work on exercises for a group, the higher you climb for that area. Your progress is clear and measurable.';
  static const String concept2Title = 'Your app for goals';
  static const String concept2Message =
      'Use the app as a tool to reach your goals: precise tracking, suggestions based on weak points, and visible progress. All in one place.';
  static const String concept3Title = 'A simple, clear experience';
  static const String concept3Message =
      'Fast tracking, explainable ranks, and a workout flow without the hassle. Start easy, progress steadily.';

  // — Entry (înainte de login: Welcome Sleek → Login)
  /// Sleek welcome screen — wordmark + headline + subtitle (matches design export).
  static const String welcomeLogoWordmark = 'Zvelt';
  static const String welcomeHeadlineTrain = 'TRAIN';
  static const String welcomeHeadlineFaster = 'FASTER';
  static const String welcomeSubtitle =
      'Personalized AI coaching for athletes who demand more from their performance.';
  static const String welcomeGetStarted = 'GET STARTED';
  static const String welcomeAlreadyHaveAccount = 'I ALREADY HAVE AN ACCOUNT';

  // — Onboarding questionnaire (FIG 8–19)
  static const String questionnaireTitle = 'Quick setup';
  static const String questionnaireUnitsTitle = 'Units';
  static const String questionnaireUnitsMessage = 'Choose your preferred units for weight and height.';
  static const String metric = 'Metric (kg, cm)';
  static const String imperial = 'Imperial (lb, in)';
  static const String questionnaireMuscleTitle = 'Main muscle focus';
  static const String questionnaireMuscleMessage = 'Select the muscle groups you want to focus on (you can change this later).';
  static const String questionnaireGoalTitle = 'Primary goal';
  static const String questionnaireGoalMessage = 'What do you want to achieve most?';
  static const String goalStrength = 'Strength';
  static const String goalMuscle = 'Muscle mass';
  static const String goalPower = 'Explosive power';
  static const String goalGeneral = 'General fitness';
  static const String questionnaireGenderTitle = 'Gender';
  static const String questionnaireGenderMessage = 'Used for ranking and recommendations.';
  static const String male = 'Male';
  static const String female = 'Female';
  static const String other = 'Other';
  static const String questionnaireHeightTitle = 'Height';
  static const String questionnaireHeightMessage = 'Your height (used for calculations).';
  static const String questionnaireWeightTitle = 'Weight';
  static const String questionnaireWeightMessage = 'Your current body weight.';
  static const String questionnaireAgeTitle = 'Age';
  static const String questionnaireAgeMessage = 'Your age or birth year.';
  static const String letsGo = "Let's go!";
  static const String questionnaireFinalTitle = "You're all set";
  static const String questionnaireFinalMessage = 'We have everything we need to personalize your experience.';

  // — Avatar flow (FIG 20–24)
  static const String avatarIntroTitle = 'Your avatar';
  static const String avatarIntroMessage =
      'Choose an avatar that represents you. It will show on your profile and reflect your progress.';
  static const String avatarChooseTitle = 'Choose your avatar';
  static const String avatarChooseHint = 'Tap one to select';
  static const String avatarNext = 'Next';
  static const String avatarConfirmTitle = 'Looking good!';
  static const String avatarConfirmMessage = "You're all set. You can change your avatar later in Profile.";

  // — Social / Race Hub
  /// Curated competitive-but-respectful quick reply chips used in the
  /// race chat composer. Keep each phrase short (fits on a chip) and
  /// non-aggressive — no personal attacks or insults.
  // TODO(v1.1): move to GET /v1/i18n/race-replies for backend curation and A/B testing.
  static const List<String> raceQuickReplies = <String>[
    "Let's race",
    'Big effort',
    'Catch me',
    'On your six',
    'Show me',
    'New PR incoming',
  ];

  // — Profile
  static const String weight = 'Weight';
  static const String height = 'Height';
  static const String weightHeightSection = 'Weight & height';
  static const String weightUnitKg = 'kg';
  static const String heightUnitCm = 'cm';
  static const String save = 'Save';
  static const String saved = 'Saved';
}
