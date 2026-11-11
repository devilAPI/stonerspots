import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../core/glass.dart';
import '../../core/location_service.dart';
import '../../core/models.dart';
import '../../core/providers.dart' show apiClientProvider;
import '../../l10n/app_localizations.dart';
import '../../core/user_avatar.dart';
import '../home_widgets/nearest_spot.dart' show formatDistance;
import '../reviews/rating_widgets.dart';
import '../users/author_link.dart'
    show AvatarOverrides, avatarOverridesProvider;
import '../users/user_search.dart';

/// Shortest query the API accepts (`GET /spots/search` and
/// `GET /users/search`, in characters).
const kSpotSearchMinLength = 2;

/// Spots by name (`GET /spots/search`): at most 20, nearest first when
/// [near] is given (they then carry `distanceM`), else best match first.
abstract class SpotSearchRepository {
  Future<List<Spot>> search(String query, {LatLng? near});
}

class ApiSpotSearchRepository implements SpotSearchRepository {
  ApiSpotSearchRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<Spot>> search(String query, {LatLng? near}) async {
    final data = await _api.get<List<dynamic>>(
      '/spots/search',
      query: {
        'q': query,
        if (near != null) 'lat': near.latitude,
        if (near != null) 'lon': near.longitude,
      },
    );
    return [for (final e in data) Spot.fromJson(e as Map<String, dynamic>)];
  }
}

final spotSearchRepositoryProvider = Provider<SpotSearchRepository>(
  (ref) => ApiSpotSearchRepository(ref.watch(apiClientProvider)),
);

/// Pause after the last keystroke before a query goes out.
final spotSearchDebounceProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 300),
);

/// What the search looks for.
enum SearchMode { spots, users }

class SpotSearchState {
  const SpotSearchState({
    this.mode = SearchMode.spots,
    this.query = '',
    this.loading = false,
    this.results,
    this.users,
    this.error = false,
  });

  final SearchMode mode;

  /// Trimmed, inner whitespace collapsed (as the API does).
  final String query;
  final bool loading;

  /// Spots for [query] (mode spots); while a newer query loads, the
  /// previous answer. Null before the first answer.
  final List<Spot>? results;

  /// Users for [query] (mode users), like [results].
  final List<UserMatch>? users;
  final bool error;

  bool get tooShort =>
      query.isNotEmpty && query.runes.length < kSpotSearchMinLength;

  /// A new query of the same mode, keeping the answer on screen.
  SpotSearchState _next(String q, {bool loading = false}) => SpotSearchState(
    mode: mode,
    query: q,
    loading: loading,
    results: loading ? results : null,
    users: loading ? users : null,
  );
}

final spotSearchControllerProvider =
    NotifierProvider.autoDispose<SpotSearchController, SpotSearchState>(
      SpotSearchController.new,
    );

class SpotSearchController extends Notifier<SpotSearchState> {
  Timer? _timer;
  int _seq = 0;

  @override
  SpotSearchState build() {
    ref.onDispose(() => _timer?.cancel());
    return const SpotSearchState();
  }

  /// Takes the field's text; searches once typing pauses.
  void setQuery(String raw) {
    final q = raw.trim().split(RegExp(r'\s+')).join(' ');
    if (q == state.query) return;
    _timer?.cancel();
    final seq = ++_seq;
    if (q.runes.length < kSpotSearchMinLength) {
      state = state._next(q);
      return;
    }
    state = state._next(q, loading: true);
    _timer = Timer(ref.read(spotSearchDebounceProvider), () => _run(q, seq));
  }

  /// Switches between spots and users; asks right away for what is typed.
  void setMode(SearchMode mode) {
    if (mode == state.mode) return;
    _timer?.cancel();
    final seq = ++_seq;
    final q = state.query;
    final ready = q.runes.length >= kSpotSearchMinLength;
    state = SpotSearchState(mode: mode, query: q, loading: ready);
    if (ready) _run(q, seq);
  }

  /// Asks again for the current query, right away.
  void retry() {
    final q = state.query;
    if (q.runes.length < kSpotSearchMinLength) return;
    _timer?.cancel();
    final seq = ++_seq;
    state = state._next(q, loading: true);
    _run(q, seq);
  }

  Future<void> _run(String q, int seq) async {
    final mode = state.mode;
    try {
      if (mode == SearchMode.users) {
        final users = await ref.read(userSearchRepositoryProvider).search(q);
        if (seq != _seq) return;
        state = SpotSearchState(mode: mode, query: q, users: users);
        return;
      }
      // Only a position this run already has: no permission prompt here.
      final near = ref.read(lastLocationLookupProvider)?.position;
      final results = await ref
          .read(spotSearchRepositoryProvider)
          .search(q, near: near);
      if (seq != _seq) return;
      state = SpotSearchState(mode: mode, query: q, results: results);
    } catch (_) {
      if (seq != _seq) return;
      state = SpotSearchState(mode: mode, query: q, error: true);
    }
  }
}

/// The search over the map: a glass capsule with the field, below it the
/// choice between spots and users and, once something is typed, a glass
/// panel with the matches.
class MapSpotSearch extends ConsumerStatefulWidget {
  const MapSpotSearch({
    super.key,
    required this.focusNode,
    required this.onPick,
    required this.onPickUser,
    required this.onClose,
  });

  final FocusNode focusNode;
  final ValueChanged<Spot> onPick;

  /// A user picked: open their profile.
  final ValueChanged<Author> onPickUser;
  final VoidCallback onClose;

  @override
  ConsumerState<MapSpotSearch> createState() => _MapSpotSearchState();
}

class _MapSpotSearchState extends ConsumerState<MapSpotSearch>
    with SingleTickerProviderStateMixin {
  final _text = TextEditingController();
  late final TabController _modeTabs = TabController(
    length: SearchMode.values.length,
    vsync: this,
    initialIndex: ref.read(spotSearchControllerProvider).mode.index,
  );

  @override
  void dispose() {
    _text.dispose();
    _modeTabs.dispose();
    super.dispose();
  }

  void _setMode(SearchMode mode) {
    ref.read(spotSearchControllerProvider.notifier).setMode(mode);
    widget.focusNode.requestFocus();
  }

  void _clear() {
    _text.clear();
    ref.read(spotSearchControllerProvider.notifier).setQuery('');
    widget.focusNode.requestFocus();
  }

  void _submit() {
    final s = ref.read(spotSearchControllerProvider);
    if (s.loading) return;
    final results = s.results;
    final users = s.users;
    if (s.mode == SearchMode.spots && results != null && results.isNotEmpty) {
      widget.onPick(results.first);
    } else if (s.mode == SearchMode.users &&
        users != null &&
        users.isNotEmpty) {
      widget.onPickUser(users.first.author);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(spotSearchControllerProvider);
    final ctrl = ref.read(spotSearchControllerProvider.notifier);
    final hint = kOnGlass.withValues(alpha: 0.6);

    final field = SizedBox(
      height: 52,
      child: GlassSurface(
        radius: 26,
        child: Row(
          children: [
            const SizedBox(width: 14),
            const Icon(Icons.search),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const Key('mapSearchField'),
                controller: _text,
                focusNode: widget.focusNode,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: ctrl.setQuery,
                onSubmitted: (_) => _submit(),
                style: const TextStyle(color: kOnGlass, fontSize: 16),
                cursorColor: kOnGlass,
                decoration: InputDecoration(
                  hintText: s.mode == SearchMode.users
                      ? l.mapSearchUserHint
                      : l.mapSearchHint,
                  hintStyle: TextStyle(color: hint),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                ),
              ),
            ),
            if (s.loading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox.square(
                  key: Key('mapSearchProgress'),
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kOnGlass,
                  ),
                ),
              ),
            if (s.query.isNotEmpty)
              IconButton(
                key: const Key('mapSearchClear'),
                tooltip: l.mapSearchClear,
                icon: const Icon(Icons.backspace_outlined, size: 20),
                onPressed: _clear,
              ),
            IconButton(
              key: const Key('mapSearchClose'),
              tooltip: l.mapSearchClose,
              icon: const Icon(Icons.close),
              onPressed: widget.onClose,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );

    final modes = GlassTabs(
      key: const Key('mapSearchMode'),
      controller: _modeTabs,
      onTap: (i) => _setMode(SearchMode.values[i]),
      tabs: [
        for (final m in SearchMode.values)
          Tab(
            key: Key('mapSearchMode-${m.name}'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  m == SearchMode.users
                      ? Icons.person_outline
                      : Icons.place_outlined,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  m == SearchMode.users
                      ? l.mapSearchModeUsers
                      : l.mapSearchModeSpots,
                ),
              ],
            ),
          ),
      ],
    );

    final body = _body(context, l, s, ctrl);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field,
          const SizedBox(height: 8),
          modes,
          if (body != null) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.5,
              ),
              child: GlassSurface(radius: 22, child: body),
            ),
          ],
        ],
      ),
    );
  }

  /// What goes below the field, or nothing yet.
  Widget? _body(
    BuildContext context,
    AppLocalizations l,
    SpotSearchState s,
    SpotSearchController ctrl,
  ) {
    Widget message(String text, {Key? key, Widget? action}) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
      child: Row(
        children: [
          Expanded(child: Text(text, key: key)),
          ?action,
        ],
      ),
    );

    if (s.query.isEmpty) return null;
    if (s.tooShort) {
      return message(l.mapSearchTooShort, key: const Key('mapSearchTooShort'));
    }
    if (s.error) {
      return message(
        l.mapSearchError,
        key: const Key('mapSearchError'),
        action: TextButton(
          key: const Key('mapSearchRetry'),
          style: TextButton.styleFrom(foregroundColor: kOnGlass),
          onPressed: ctrl.retry,
          child: Text(l.retry),
        ),
      );
    }
    if (s.mode == SearchMode.users) return _users(l, s);
    final results = s.results;
    if (results == null) return null; // first answer still on its way
    if (results.isEmpty) {
      if (s.loading) return null;
      return message(l.mapSearchNoResult, key: const Key('mapSearchEmpty'));
    }
    final lang = Localizations.localeOf(context).languageCode;
    return ListView.builder(
      key: const Key('mapSearchResults'),
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final spot = results[i];
        final distance = spot.distanceM;
        final hasRating = spot.ratingCount > 0;
        return ListTile(
          key: Key('mapSearchResult-${spot.id}'),
          dense: true,
          textColor: kOnGlass,
          iconColor: kOnGlass,
          leading: const Icon(Icons.place_outlined),
          title: Text(spot.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: distance == null && !hasRating
              ? null
              : Row(
                  children: [
                    if (distance != null)
                      Text(
                        formatDistance(distance, lang),
                        key: Key('mapSearchDistance-${spot.id}'),
                      ),
                    if (distance != null && hasRating)
                      const SizedBox(width: 12),
                    if (hasRating)
                      RatingBadge(
                        avg: spot.ratingAvg,
                        count: spot.ratingCount,
                        size: 14,
                      ),
                  ],
                ),
          onTap: () => widget.onPick(spot),
        );
      },
    );
  }

  /// The users matching the query, or a message.
  Widget? _users(AppLocalizations l, SpotSearchState s) {
    final users = s.users;
    if (users == null) return null; // first answer still on its way
    if (users.isEmpty) {
      if (s.loading) return null;
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
        child: Text(l.mapSearchNoUser, key: const Key('mapSearchEmpty')),
      );
    }
    final overrides = ref.watch(avatarOverridesProvider);
    return ListView.builder(
      key: const Key('mapSearchResults'),
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: users.length,
      itemBuilder: (context, i) {
        final u = users[i].author;
        return ListTile(
          key: Key('mapSearchUser-${u.id}'),
          dense: true,
          textColor: kOnGlass,
          iconColor: kOnGlass,
          leading: UserAvatar(
            userId: u.id,
            name: u.displayName,
            url: AvatarOverrides.resolve(overrides, u.id, u.avatarUrl),
            radius: 16,
          ),
          title: Text(
            u.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(l.mapSearchUserSpots(users[i].spotCount)),
          onTap: () => widget.onPickUser(u),
        );
      },
    );
  }
}

/// The button that opens the search. While its page is the one on screen
/// it also takes the keyboard shortcuts Ctrl+K (Cmd+K) and `/`; `/` is left
/// to text fields that have focus.
class MapSearchButton extends StatefulWidget {
  const MapSearchButton({
    super.key,
    required this.onPressed,
    this.visible = true,
  });

  final VoidCallback onPressed;

  /// Off: no button, only the keyboard shortcuts.
  final bool visible;

  @override
  State<MapSearchButton> createState() => _MapSearchButtonState();
}

class _MapSearchButtonState extends State<MapSearchButton> {
  @override
  void initState() {
    super.initState();
    // Global, not a Shortcuts widget: on a fresh page nothing has focus yet,
    // and Shortcuts only see keys of the focused subtree.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Whether this page is what the user sees: its tab is the selected one
  /// and no page, sheet or dialog lies above it at any level.
  bool _onScreen() {
    if (!TickerMode.valuesOf(context).enabled) return false;
    BuildContext? c = context;
    while (c != null) {
      final route = ModalRoute.of(c);
      if (route == null) return true;
      if (!route.isCurrent) return false;
      c = route.navigator?.context;
    }
    return true;
  }

  static bool _typing() {
    final focused = FocusManager.instance.primaryFocus?.context;
    return focused != null &&
        (focused.widget is EditableText ||
            focused.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    final keys = HardwareKeyboard.instance;
    final command = keys.isControlPressed || keys.isMetaPressed;
    final bool hit;
    if (event.logicalKey == LogicalKeyboardKey.keyK) {
      hit = command && !keys.isAltPressed;
    } else {
      // `/` sits on Shift+7 on German keyboards: compare the character.
      hit =
          !command &&
          !keys.isAltPressed &&
          (event.character == '/' ||
              event.logicalKey == LogicalKeyboardKey.slash ||
              event.logicalKey == LogicalKeyboardKey.numpadDivide) &&
          !_typing();
    }
    if (!hit || !_onScreen()) return false;
    widget.onPressed();
    return true;
  }

  @override
  Widget build(BuildContext context) => !widget.visible
      ? const SizedBox.shrink()
      : IconButton(
          key: const Key('mapSearchOpen'),
          tooltip: AppLocalizations.of(context).mapSearch,
          onPressed: widget.onPressed,
          icon: const Icon(Icons.search),
        );
}
