import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/recording/presentation/screens/recording_detail_screen.dart';
import '../../features/recording/presentation/screens/recording_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/subjects/presentation/screens/subjects_screen.dart';
import '../../features/transcript/presentation/screens/transcripts_screen.dart';
import '../../shared/widgets/app_scaffold.dart';

/// Route names as constants for type-safe navigation
class AppRoutes {
  AppRoutes._();

  static const String splash = '/splash';
  static const String home = '/home';
  static const String subjects = '/subjects';
  static const String record = '/record';
  static const String transcripts = '/transcripts';
  static const String settings = '/settings';
  static const String recordingDetail = '/recording/:id';
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

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.home,
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
        path: AppRoutes.record,
        builder: (context, state) =>
            const RecordingScreen(),
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
