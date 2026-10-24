import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../core/coordinates.dart';
import '../../l10n/app_localizations.dart';
import 'add_spot_controller.dart';
import 'geocode_repository.dart';
import 'location_picker.dart';

const int kMinSearchLength = 3;

enum PlaceSearchMessage {
  tooShort,
  noResult,
  outsideRegion,
  shortLink,
  rateLimited,
  unavailable,
  error,
}

class PlaceSearchState {
  const PlaceSearchState({
    this.searching = false,
    this.results = const [],
    this.message,
    this.focus,
  });

  final bool searching;
  final List<GeoResult> results;
  final PlaceSearchMessage? message;

  /// Latest recentre request for the map (see [MapFocus]).
  final MapFocus? focus;

  PlaceSearchState copyWith({
    bool? searching,
    List<GeoResult>? results,
    PlaceSearchMessage? message,
    bool clearMessage = false,
    MapFocus? focus,
  }) => PlaceSearchState(
    searching: searching ?? this.searching,
    results: results ?? this.results,
    message: clearMessage ? null : (message ?? this.message),
    focus: focus ?? this.focus,
  );
}

final placeSearchControllerProvider =
    NotifierProvider.autoDispose<PlaceSearchController, PlaceSearchState>(
      PlaceSearchController.new,
    );

class PlaceSearchController extends Notifier<PlaceSearchState> {
  int _seq = 0;

  @override
  PlaceSearchState build() => const PlaceSearchState();

  void _place(LatLng p) {
    state = PlaceSearchState(focus: MapFocus(p));
    ref.read(addSpotControllerProvider.notifier).setPoint(p);
  }

  /// Runs on Enter / the search button only (no search-as-you-type).
  Future<void> submit(String raw) async {
    final text = raw.trim();
    final seq = ++_seq;
    final keepFocus = state.focus;
    PlaceSearchState only({
      PlaceSearchMessage? message,
      bool searching = false,
    }) => PlaceSearchState(
      message: message,
      searching: searching,
      focus: keepFocus,
    );

    if (isShortMapLink(text)) {
      state = only(message: PlaceSearchMessage.shortLink);
      return;
    }
    final p = parseCoordinates(text);
    if (p != null) {
      if (inSupportedRegion(p)) {
        _place(p);
      } else {
        state = only(message: PlaceSearchMessage.outsideRegion);
      }
      return;
    }
    if (text.length < kMinSearchLength) {
      state = only(message: text.isEmpty ? null : PlaceSearchMessage.tooShort);
      return;
    }
    state = only(searching: true);
    try {
      final results = await ref.read(geocodeRepositoryProvider).search(text);
      if (seq != _seq) return;
      state = PlaceSearchState(
        results: results,
        message: results.isEmpty ? PlaceSearchMessage.noResult : null,
        focus: keepFocus,
      );
    } catch (e) {
      if (seq != _seq) return;
      final code = e is ApiException ? e.code : '';
      state = only(
        message: switch (code) {
          'rate_limited' => PlaceSearchMessage.rateLimited,
          'geocoder_unavailable' ||
          'geocoder_busy' => PlaceSearchMessage.unavailable,
          'invalid_query' => PlaceSearchMessage.tooShort,
          _ => PlaceSearchMessage.error,
        },
      );
    }
  }

  void select(GeoResult r) {
    _seq++;
    _place(LatLng(r.lat, r.lon));
  }

  /// Hides results/messages and ignores any response still in flight.
  void dismiss() {
    _seq++;
    state = PlaceSearchState(focus: state.focus);
  }
}

class PlaceSearchField extends ConsumerStatefulWidget {
  const PlaceSearchField({super.key});

  @override
  ConsumerState<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends ConsumerState<PlaceSearchField> {
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() =>
      ref.read(placeSearchControllerProvider.notifier).submit(_text.text);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(placeSearchControllerProvider);
    final ctrl = ref.read(placeSearchControllerProvider.notifier);
    final theme = Theme.of(context);
    final message = s.message == null ? null : _messageText(l, s.message!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('placeSearch'),
          controller: _text,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _submit(),
          onChanged: (_) {
            if (s.results.isNotEmpty || s.message != null) ctrl.dismiss();
          },
          decoration: InputDecoration(
            hintText: l.placeSearchHint,
            prefixIcon: IconButton(
              key: const Key('placeSearchGo'),
              tooltip: l.placeSearchGo,
              icon: const Icon(Icons.search),
              onPressed: _submit,
            ),
            suffixIcon: s.searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      key: Key('placeSearchProgress'),
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _text.text.isEmpty
                ? null
                : IconButton(
                    key: const Key('placeSearchClear'),
                    tooltip: l.placeSearchClear,
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _text.clear();
                      ctrl.dismiss();
                    },
                  ),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              message,
              key: const Key('placeSearchMessage'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        for (var i = 0; i < s.results.length; i++)
          ListTile(
            key: Key('placeResult-$i'),
            dense: true,
            leading: const Icon(Icons.place_outlined),
            title: Text(
              s.results[i].label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              _text.text = s.results[i].label;
              ctrl.select(s.results[i]);
            },
          ),
      ],
    );
  }

  String _messageText(AppLocalizations l, PlaceSearchMessage m) => switch (m) {
    PlaceSearchMessage.tooShort => l.placeSearchTooShort,
    PlaceSearchMessage.noResult => l.placeSearchNoResult,
    PlaceSearchMessage.outsideRegion => l.placeSearchOutside,
    PlaceSearchMessage.shortLink => l.placeSearchShortLink,
    PlaceSearchMessage.rateLimited => l.placeSearchRateLimited,
    PlaceSearchMessage.unavailable => l.placeSearchUnavailable,
    PlaceSearchMessage.error => l.placeSearchError,
  };
}
