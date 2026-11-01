import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/glass.dart';
import '../../core/models.dart';
import '../spots/spot_detail_screen.dart';
import 'spot_preview_sheet.dart';

const double _margin = 8;
const double _radius = 32;
const double _grabberHeight = 13;

/// Opens the spot preview as a card that can be pulled up into the spot page.
Future<void> showSpotPullSheet(BuildContext context, Spot spot) {
  // The sheet's route strips the top padding, the real page keeps it.
  final media = MediaQuery.of(
    Navigator.of(context, rootNavigator: true).context,
  );
  final id = spot.id;
  return showModalBottomSheet<void>(
    context: context,
    // above the floating tab bar, which lives outside this tab's navigator
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    // the sheet drags itself, see SpotPullSheet
    enableDrag: false,
    builder: (sheetContext) => Consumer(
      builder: (_, ref, child) {
        // Loaded and kept for the page, so it is ready when pulled up.
        ref.watch(spotDetailProvider(id));
        ref.watch(spotUpdatesProvider(id));
        return child!;
      },
      child: SpotPullSheet(
        spot: spot,
        page: MediaQuery(
          data: media,
          child: SpotDetailScreen(spotId: id),
        ),
        onOpen: () {
          Navigator.of(sheetContext).pop();
          context.push('/spot/$id');
        },
        onExpanded: () => context.push('/spot/$id', extra: kSpotFromSheet),
      ),
    ),
  );
}

/// The card and, fading in behind it while it is pulled up, [page] at its
/// final size. Fully open it looks exactly like the real page, so
/// [onExpanded] can show that page without a visible change; this sheet then
/// removes itself from beneath it.
class SpotPullSheet extends StatefulWidget {
  const SpotPullSheet({
    super.key,
    required this.spot,
    required this.page,
    required this.onOpen,
    required this.onExpanded,
  });

  final Spot spot;
  final Widget page;
  final VoidCallback onOpen;
  final VoidCallback onExpanded;

  @override
  State<SpotPullSheet> createState() => _SpotPullSheetState();
}

class _SpotPullSheetState extends State<SpotPullSheet> {
  final _cardKey = GlobalKey();

  /// Share of the screen the card rests at; null until it has been measured.
  double? _rest;
  late final _extent = ValueNotifier<double>(0);
  bool _handedOver = false;

  @override
  void dispose() {
    _extent.dispose();
    super.dispose();
  }

  void _measure(Duration _) {
    if (!mounted) return;
    final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final height = MediaQuery.sizeOf(context).height;
    setState(() {
      _rest = math.min((box.size.height + _margin) / height, 0.9);
      _extent.value = _rest!;
    });
  }

  bool _onExtent(DraggableScrollableNotification n) {
    _extent.value = n.extent;
    if (n.extent >= 0.999 && !_handedOver) {
      _handedOver = true;
      final route = ModalRoute.of(context)!;
      widget.onExpanded();
      _removeOnceCovered(route);
    }
    return false; // the modal route closes itself on the minimum extent
  }

  /// Takes the sheet out without its closing animation, a frame after the
  /// page has gone on top of it.
  void _removeOnceCovered(ModalRoute<dynamic> route) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isCurrent) return _removeOnceCovered(route);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Widget _card(ScrollController? scroll) => SpotPreviewSheet(
    spot: widget.spot,
    onOpen: widget.onOpen,
    scrollController: scroll,
    header: const SizedBox(
      width: double.infinity,
      height: _grabberHeight,
      child: Align(alignment: Alignment.topCenter, child: _Grabber()),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final rest = _rest;
    if (rest == null) {
      WidgetsBinding.instance.addPostFrameCallback(_measure);
      return Align(
        alignment: Alignment.bottomCenter,
        child: Opacity(
          opacity: 0,
          child: KeyedSubtree(key: _cardKey, child: _card(null)),
        ),
      );
    }
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: _onExtent,
      // Scrollables ignore mouse drags by default; the sheet has to follow
      // them too, or it cannot be pulled in a desktop browser.
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context)
            .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: rest,
          // Below the resting size it snaps shut; the route closes at 0.
          minChildSize: 0,
          snap: true,
          snapSizes: [rest],
          snapAnimationDuration: const Duration(milliseconds: 240),
          builder: (context, scroll) => ValueListenableBuilder<double>(
            valueListenable: _extent,
            child: _card(scroll),
            builder: (context, extent, card) =>
                _layers(context, rest, extent, card!),
          ),
        ),
      ),
    );
  }

  Widget _layers(
    BuildContext context,
    double rest,
    double extent,
    Widget card,
  ) {
    final t = ((extent - rest) / (1 - rest)).clamp(0.0, 1.0);
    final size = MediaQuery.sizeOf(context);
    final radius = _radius * (1 - t);
    final margin = _margin * (1 - t);
    return Padding(
      padding: EdgeInsets.fromLTRB(margin, 0, margin, margin),
      child: Stack(
        children: [
          Positioned.fill(
            child: GlassPanel(
              radius: radius,
              // solid by the time the page has faded in
              color: Color.lerp(
                glassTint(context),
                Theme.of(context).scaffoldBackgroundColor,
                t,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: (1 - t * 3).clamp(0.0, 1.0),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: kOnGlass),
                child: IconTheme.merge(
                  data: const IconThemeData(color: kOnGlass),
                  child: Material(type: MaterialType.transparency, child: card),
                ),
              ),
            ),
          ),
          if (t > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: Opacity(
                    opacity: ((t - 0.2) / 0.5).clamp(0.0, 1.0),
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minWidth: size.width,
                      maxWidth: size.width,
                      minHeight: size.height,
                      maxHeight: size.height,
                      child: widget.page,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    height: 5,
    decoration: BoxDecoration(
      color: const Color(0x66FFFFFF),
      borderRadius: BorderRadius.circular(3),
    ),
  );
}
