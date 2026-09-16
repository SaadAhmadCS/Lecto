import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/screens/auth_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/onboarding/presentation/screens/first_subject_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/recording/presentation/screens/recording_detail_screen.dart';
import '../../features/recording/presentation/screens/recording_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/subjects/presentation/screens/subject_detail_screen.dart';
import '../../features/subjects/presentation/screens/subjects_screen.dart';
import '../../features/transcript/presentation/screens/transcripts_screen.dart';
import '../../shared/widgets/app_scaffold.dart';

/// Route names as constants for type-safe navigation
class AppRoutes {
  AppRoutes._();

  static const String auth = '/auth';
  static const String splash = '/splash';
  static const String home = '/home';
  static const String subjects = '/subjects';
  static const String subjectDetail = '/subjects/:id';
  static const String record = '/record';
  static const String transcripts = '/transcripts';
  static const String settings = '/settings';
  static const String recordingDetail = '/recording/:id';
  static const String onboarding = '/onboarding';
  static const String firstSubject = '/onboarding/first-subject';
}

/// GoRouter configuration for Lecto
///
/// Uses ShellRoute for bottom navigation with
/// persistent state.
class AppRouter {
  AppRouter._();

  static final _rootNavigatorKey =
      GlobalKey<NavigatorState>();
  static final _shellNavigatorKey =
      GlobalKey<NavigatorState>();

  static GoRouter router({
    bool showOnboarding = false,
    bool isAuthenticated = true,
  }) => GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: !isAuthenticated 
        ? AppRoutes.auth 
        : (showOnboarding ? AppRoutes.onboarding : AppRoutes.home),
    routes: [
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          return AppScaffold(child: child);
        },
        routes: [
          GoRoute(
            path: AppRoutes.home,
            pageBuilder: (context, state) =>
                const NoTransitionPage(
              child: HomeScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.subjects,
            pageBuilder: (context, state) =>
                const NoTransitionPage(
              child: SubjectsScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.transcripts,
            pageBuilder: (context, state) =>
                const NoTransitionPage(
              child: TranscriptsScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.settings,
            pageBuilder: (context, state) =>
                const NoTransitionPage(
              child: SettingsScreen(),
            ),
          ),
        ],
      ),
      // Full-screen routes (outside shell)
      GoRoute(
        path: AppRoutes.auth,
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.firstSubject,
        builder: (context, state) => const FirstSubjectScreen(),
      ),
      GoRoute(
        path: AppRoutes.subjectDetail,
        builder: (context, state) => SubjectDetailScreen(
          subjectId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.record,
        builder: (context, state) => RecordingScreen(
          initialSubjectId: state.uri.queryParameters['subjectId'],
        ),
      ),
      GoRoute(
        path: AppRoutes.recordingDetail,
        builder: (context, state) {
          final recordingId = state.pathParameters['id']!;
          final title = state.uri.queryParameters['title'] ?? 'Recording';
          return RecordingDetailScreen(
            recordingId: recordingId,
            title: title,
          );
        },
      ),
    ],
  );
}
