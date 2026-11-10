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
import '../home_widgets/nearest_spot.dart' show formatDistance;
import '../reviews/rating_widgets.dart';

/// Shortest query the API accepts (`GET /spots/search`, in characters).
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

class SpotSearchState {
  const SpotSearchState({
    this.query = '',
    this.loading = false,
    this.results,
    this.error = false,
  });

  /// Trimmed, inner whitespace collapsed (as the API does).
  final String query;
  final bool loading;

  /// Answer for [query]; while a newer query loads, the previous answer.
  /// Null before the first answer.
  final List<Spot>? results;
  final bool error;

  bool get tooShort =>
      query.isNotEmpty && query.runes.length < kSpotSearchMinLength;
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
      state = SpotSearchState(query: q);
      return;
    }
    state = SpotSearchState(query: q, loading: true, results: state.results);
    _timer = Timer(ref.read(spotSearchDebounceProvider), () => _run(q, seq));
  }

  /// Asks again for the current query, right away.
  void retry() {
    final q = state.query;
    if (q.runes.length < kSpotSearchMinLength) return;
    _timer?.cancel();
    final seq = ++_seq;
    state = SpotSearchState(query: q, loading: true, results: state.results);
    _run(q, seq);
  }

  Future<void> _run(String q, int seq) async {
    try {
      // Only a position this run already has: no permission prompt here.
      final near = ref.read(lastLocationLookupProvider)?.position;
      final results = await ref
          .read(spotSearchRepositoryProvider)
          .search(q, near: near);
      if (seq != _seq) return;
      state = SpotSearchState(query: q, results: results);
    } catch (_) {
      if (seq != _seq) return;
      state = SpotSearchState(query: q, error: true);
    }
  }
}

/// The search over the map: a glass capsule with the field and, once
/// something is typed, a glass panel with the matches below it.
class MapSpotSearch extends ConsumerStatefulWidget {
  const MapSpotSearch({
    super.key,
    required this.focusNode,
    required this.onPick,
    required this.onClose,
  });

  final FocusNode focusNode;
  final ValueChanged<Spot> onPick;
  final VoidCallback onClose;

  @override
  ConsumerState<MapSpotSearch> createState() => _MapSpotSearchState();
}

class _MapSpotSearchState extends ConsumerState<MapSpotSearch> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _clear() {
    _text.clear();
    ref.read(spotSearchControllerProvider.notifier).setQuery('');
    widget.focusNode.requestFocus();
  }

  void _submit() {
    final s = ref.read(spotSearchControllerProvider);
    final results = s.results;
    if (!s.loading && results != null && results.isNotEmpty) {
      widget.onPick(results.first);
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
                  hintText: l.mapSearchHint,
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
