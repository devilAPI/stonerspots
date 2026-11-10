import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/activity/activity_bell.dart';
import 'features/activity/activity_screen.dart';
import 'features/admin/admin_code_dialog.dart';
import 'features/admin/admin_screen.dart';
import 'features/admin/admin_two_factor_card.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/profile_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/feed/feed_screen.dart';
import 'features/legal/legal_pages.dart';
import 'core/glass.dart';
import 'core/adaptive_nav.dart';
import 'core/models.dart' show User;
import 'core/providers.dart' show apiClientProvider;
import 'core/back_or_home.dart';
import 'core/tab_keys.dart';
import 'features/map/map_search_request.dart';
import 'features/map/map_screen.dart';
import 'features/saved/saved_list_screen.dart';
import 'features/saved/saved_lists_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/spots/add_spot_screen.dart';
import 'features/spots/spot_detail_screen.dart';
import 'features/users/user_profile_screen.dart';
import 'l10n/app_localizations.dart';

/// Routes that need a logged-in user. The map, feed and spot detail are public.
const _protectedPaths = {'/spot/new'};

/// Returns the redirect target for [location], or null to stay.
String? authRedirect({
  required bool loggedIn,
  required String location,
  bool isAdmin = false,
}) {
  final saved = location == '/saved' || location.startsWith('/saved/');
  final admin = location == '/admin' || location.startsWith('/admin/');
  if (!loggedIn &&
      (_protectedPaths.contains(location) ||
          saved ||
          admin ||
          location == '/activity')) {
    return '/login?from=${Uri.encodeComponent(location)}';
  }
  if (loggedIn && !isAdmin && admin) return '/';
  return null;
}

/// What the redirects depend on: `out`, or `<id>:<admin>`.
String authAccess(User? u) => u == null ? 'out' : '${u.id}:${u.isAdmin}';

/// Whether the router must re-run its redirects when the settled login
/// state goes from [before] (null: still restoring) to [now]. Not on
/// login: no page a logged-out user can be on becomes forbidden, and the
/// refresh would re-apply the route list from before the login page closed
/// itself, opening it again.
bool redirectsMayChange(String? before, String now) =>
    now != before && !(before == 'out' && now != 'out');

class _ScaffoldWithNav extends ConsumerWidget {
  const _ScaffoldWithNav({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return TabKeys(
      count: 3,
      index: shell.currentIndex,
      onSelect: shell.goBranch,
      child: AdaptiveNavScaffold(
        selectedIndex: shell.currentIndex,
        onSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        // iOS 27's search button: back to the map's own page, search open
        action: GlassBarAction(
          key: const Key('navSearch'),
          icon: Icons.search,
          label: l10n.mapSearch,
          onPressed: () {
            shell.goBranch(0, initialLocation: true);
            ref.read(mapSearchRequestProvider.notifier).open();
          },
        ),
        items: [
          NavItem(Icons.map_outlined, l10n.navMap),
          NavItem(Icons.dynamic_feed_outlined, l10n.navFeed),
          NavItem(Icons.person_outline, l10n.navProfile),
        ],
        // The profile tab (index 2) carries the activity bell.
        body: ActivityRefresher(
          profileShown: shell.currentIndex == 2,
          child: shell,
        ),
      ),
    );
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  String? settled; // null while the stored session is restored
  ref.listen(authControllerProvider, (_, next) {
    if (next.isLoading) return;
    final now = authAccess(next.value);
    if (redirectsMayChange(settled, now)) refresh.value++;
    settled = now;
  });
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    // Dialogs from outside the widget tree (the admin 2FA prompt) open on it.
    navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'root'),
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      // While the stored session is being restored, do not bounce to login.
      if (auth.isLoading && !auth.hasValue) return null;
      return authRedirect(
        loggedIn: auth.value != null,
        location: state.uri.path,
        isAdmin: auth.value?.isAdmin ?? false,
      );
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => _ScaffoldWithNav(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/', builder: (_, _) => const MapScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/feed', builder: (_, _) => const FeedScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      // '/spot/new' must come before '/spot/:id'.
      // Pages outside the shell can be alone on the stack; system back then
      // goes home (their app bars do the same, see BackOrHomeButton).
      GoRoute(
        path: '/spot/new',
        builder: (_, _) => const BackToHomeScope(child: AddSpotScreen()),
      ),
      GoRoute(
        path: '/spot/:id',
        pageBuilder: (_, state) {
          final page = BackToHomeScope(
            child: SpotDetailScreen(
              spotId: int.parse(state.pathParameters['id']!),
            ),
          );
          if (state.extra != kSpotFromSheet) {
            return MaterialPage(key: state.pageKey, child: page);
          }
          // The pulled-up sheet is already showing this page; back slides
          // it down again, like the sheet would.
          return CustomTransitionPage(
            key: state.pageKey,
            child: page,
            transitionDuration: Duration.zero,
            reverseTransitionDuration: const Duration(milliseconds: 280),
            transitionsBuilder: (_, animation, _, child) => SlideTransition(
              position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                  .animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
          );
        },
      ),
      GoRoute(
        path: '/saved',
        builder: (_, _) => const BackToHomeScope(child: SavedListsScreen()),
      ),
      GoRoute(
        path: '/saved/:id',
        builder: (_, state) => BackToHomeScope(
          // anything that is no id shows as a list that does not exist
          child: SavedListScreen(
            listId: int.tryParse(state.pathParameters['id']!) ?? 0,
          ),
        ),
      ),
      GoRoute(
        path: '/user/:id',
        builder: (_, state) => BackToHomeScope(
          // anything that is no id shows as a user that does not exist
          child: UserProfileScreen(
            userId: int.tryParse(state.pathParameters['id']!) ?? 0,
          ),
        ),
      ),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const BackToHomeScope(child: ActivityScreen()),
      ),
      GoRoute(
        path: '/login',
        builder: (_, state) => BackToHomeScope(
          child: LoginScreen(redirectTo: state.uri.queryParameters['from']),
        ),
      ),
      GoRoute(
        path: '/admin',
        builder: (_, _) => const BackToHomeScope(child: AdminScreen()),
      ),
      GoRoute(
        path: kAdminTwoFactorPath,
        builder: (_, _) => const BackToHomeScope(child: AdminTwoFactorScreen()),
      ),
      GoRoute(
        path: '/register',
        builder: (_, _) => const BackToHomeScope(child: RegisterScreen()),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const BackToHomeScope(child: SettingsScreen()),
      ),
      // public, logged in or not, and linkable from outside (web)
      GoRoute(
        path: kImprintPath,
        builder: (_, _) => const BackToHomeScope(child: ImprintScreen()),
      ),
      GoRoute(
        path: kPrivacyPath,
        builder: (_, _) => const BackToHomeScope(child: PrivacyScreen()),
      ),
      GoRoute(
        path: kRulesPath,
        builder: (_, _) => const BackToHomeScope(child: RulesScreen()),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Lets the API client ask the admin for a 2FA code (a dialog on the root
/// navigator) and sends admins who must set up 2FA first to its page. Watch
/// it once at the top of the app.
final adminTwoFactorPromptsProvider = Provider<void>((ref) {
  final api = ref.watch(apiClientProvider);
  final router = ref.watch(routerProvider);
  api.onAdminCodeNeeded = (reason) async {
    final context = router.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return null;
    return showAdminCodeDialog(context, reason);
  };
  // Several requests are refused at once (the admin page loads its lists
  // together): open the page once.
  DateTime? opened;
  api.onAdminSetupRequired = () {
    final now = DateTime.now();
    final here = router.routerDelegate.currentConfiguration.uri.path;
    if (here == kAdminTwoFactorPath) return;
    if (opened != null &&
        now.difference(opened!) < const Duration(seconds: 3)) {
      return;
    }
    opened = now;
    router.push(kAdminTwoFactorPath);
  };
  ref.onDispose(() {
    api.onAdminCodeNeeded = null;
    api.onAdminSetupRequired = null;
  });
});
