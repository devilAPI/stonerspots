import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/profile_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/feed/feed_screen.dart';
import 'features/map/map_screen.dart';
import 'features/spots/add_spot_screen.dart';
import 'features/spots/spot_detail_screen.dart';
import 'l10n/app_localizations.dart';

/// Routes that need a logged-in user. The map, feed and spot detail are public.
const _protectedPaths = {'/spot/new'};

/// Returns the redirect target for [location], or null to stay.
String? authRedirect({required bool loggedIn, required String location}) {
  if (!loggedIn && _protectedPaths.contains(location)) {
    return '/login?from=${Uri.encodeComponent(location)}';
  }
  return null;
}

class _ScaffoldWithNav extends StatelessWidget {
  const _ScaffoldWithNav({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.map_outlined), label: l10n.navMap),
          NavigationDestination(
              icon: const Icon(Icons.dynamic_feed_outlined),
              label: l10n.navFeed),
          NavigationDestination(
              icon: const Icon(Icons.person_outline), label: l10n.navProfile),
        ],
      ),
    );
  }
}

final routerProvider =Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      // While the stored session is being restored, do not bounce to login.
      if (auth.isLoading && !auth.hasValue) return null;
      return authRedirect(
          loggedIn: auth.value != null, location: state.uri.path);
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => _ScaffoldWithNav(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (_, _) => const MapScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/feed', builder: (_, _) => const FeedScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          ]),
        ],
      ),
      // '/spot/new' must come before '/spot/:id'.
      GoRoute(path: '/spot/new', builder: (_, _) => const AddSpotScreen()),
      GoRoute(
        path: '/spot/:id',
        builder: (_, state) =>
            SpotDetailScreen(spotId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/login',
        builder: (_, state) =>
            LoginScreen(redirectTo: state.uri.queryParameters['from']),
      ),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
