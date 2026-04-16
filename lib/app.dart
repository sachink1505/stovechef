import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/theme.dart';
import 'screens/auth_screen.dart';
import 'screens/browse_recipes_screen.dart';
import 'screens/cooking_mode_screen.dart';
import 'screens/create_recipe_screen.dart';
import 'screens/home_screen.dart';
import 'screens/main_shell.dart';
import 'screens/personal_details_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/recipe_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/supabase_service.dart';
import 'widgets/offline_banner.dart';

// ──────────────────────────────────────────────────────────────
// Auth refresh notifier
// Listens to Supabase auth state changes and tells GoRouter to
// re-evaluate its redirect logic.
// ──────────────────────────────────────────────────────────────

class _AuthNotifier extends ChangeNotifier {
  late final StreamSubscription<AuthState> _sub;

  _AuthNotifier() {
    _sub = SupabaseService.instance.onAuthStateChange.listen((_) {
      _profileComplete = null; // invalidate cached profile check
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final _authNotifier = _AuthNotifier();

// Cached result of isProfileComplete — reset whenever auth state changes.
bool? _profileComplete;

/// Call this after the profile is updated to clear the cached value,
/// so the router redirect re-checks profile completeness.
void resetProfileCompleteCache() {
  _profileComplete = null;
}

Future<bool> _checkProfileComplete() async {
  try {
    return await SupabaseService.instance.isProfileComplete();
  } catch (_) {
    return false;
  }
}

// ──────────────────────────────────────────────────────────────
// Router
// ──────────────────────────────────────────────────────────────

final _router = GoRouter(
  initialLocation: '/welcome',
  refreshListenable: _authNotifier,

  redirect: (context, state) async {
    final user = SupabaseService.instance.getCurrentUser();
    final location = state.matchedLocation;

    // ── Not authenticated ─────────────────────────────────────
    if (user == null) {
      _profileComplete = null;
      // Allow welcome and auth pages through; redirect everything else.
      if (location == '/welcome' || location == '/auth') return null;
      return '/welcome';
    }

    // ── Authenticated ─────────────────────────────────────────
    // Lazily fetch and cache profile completeness.
    _profileComplete ??= await _checkProfileComplete();
    final complete = _profileComplete!;

    // Redirect away from auth pages to the appropriate destination.
    if (location == '/welcome' || location == '/auth') {
      return complete ? '/home' : '/personal-details';
    }

    // Guard all other routes: if profile is incomplete, go finish it.
    if (location != '/personal-details' && !complete) {
      return '/personal-details';
    }

    return null;
  },

  routes: [
    GoRoute(
      path: '/welcome',
      pageBuilder: (context, state) =>
          _slidePage(state, const WelcomeScreen()),
    ),
    GoRoute(
      path: '/auth',
      // /welcome → /auth: slide up from bottom.
      pageBuilder: (context, state) =>
          _slideUpPage(state, const AuthScreen()),
    ),
    GoRoute(
      path: '/personal-details',
      pageBuilder: (context, state) =>
          _slidePage(state, const PersonalDetailsScreen()),
    ),

    // Shell with bottom navigation (Home + Browse tabs)
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          MainShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const HomeScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/browse',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const BrowseRecipesScreen()),
            ),
          ],
        ),
      ],
    ),

    GoRoute(
      path: '/profile',
      pageBuilder: (context, state) =>
          _slidePage(state, const ProfileScreen()),
    ),
    GoRoute(
      path: '/create-recipe',
      // URL is passed as a query parameter: /create-recipe?url=<encoded>
      pageBuilder: (context, state) => _slidePage(
        state,
        CreateRecipeScreen(
          youtubeUrl: state.uri.queryParameters['url'],
        ),
      ),
    ),
    GoRoute(
      path: '/recipe/:id',
      pageBuilder: (context, state) => _slidePage(
        state,
        RecipeScreen(recipeId: state.pathParameters['id']!),
      ),
      routes: [
        GoRoute(
          path: 'cook',
          // /recipe/:id → /recipe/:id/cook: fade transition.
          pageBuilder: (context, state) => _fadePage(
            state,
            CookingModeScreen(recipeId: state.pathParameters['id']!),
          ),
        ),
      ],
    ),
  ],
);

// ──────────────────────────────────────────────────────────────
// Page transition helpers
// ──────────────────────────────────────────────────────────────

/// No transition — used for tabs inside the shell.
CustomTransitionPage<void> _noTransitionPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (_, _, _, child) => child,
  );
}

/// Default: slide in from the right.
CustomTransitionPage<void> _slidePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeInOut),
        ),
        child: child,
      );
    },
  );
}

/// /welcome → /auth: slide up from the bottom.
CustomTransitionPage<void> _slideUpPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeInOut),
        ),
        child: child,
      );
    },
  );
}

/// /recipe/:id → /recipe/:id/cook: fade in.
CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 500),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

// ──────────────────────────────────────────────────────────────
// App
// ──────────────────────────────────────────────────────────────

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'StoveChef',
      theme: AppTheme.lightTheme(),
      routerConfig: _router,
      builder: (context, child) => Stack(
        children: [
          child!,
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: OfflineBanner(),
          ),
        ],
      ),
    );
  }
}
