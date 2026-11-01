import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_controller.dart';
import 'save_to_list_sheet.dart';
import 'saved_controller.dart';

/// How long the "saved" notice stays.
const Duration kSavedNoticeDuration = Duration(seconds: 4);

/// The bookmark of a spot, filled when the spot is in any list. A tap saves
/// to Favourites; a spot that is saved already must not get lost to a stray
/// tap, so that opens the list sheet, as a long press always does.
class SaveSpotButton extends ConsumerWidget {
  const SaveSpotButton({
    super.key,
    required this.spotId,
    this.iconOnly = false,
    this.color,
  });

  final int spotId;

  /// A plain icon button instead of a labelled capsule.
  final bool iconOnly;
  final Color? color;

  bool _needsLogin(BuildContext context, WidgetRef ref) {
    if (ref.read(authControllerProvider).value != null) return false;
    // pushed: after logging in it pops back to here
    context.push('/login');
    return true;
  }

  Future<void> _tap(BuildContext context, WidgetRef ref) async {
    if (_needsLogin(context, ref)) return;
    final provider = spotSavedProvider(spotId);
    final controller = ref.read(provider.notifier);
    final inLists = await ref
        .read(provider.future)
        .catchError((Object _) => const <int>{});
    if (!context.mounted) return;
    if (inLists.isNotEmpty) {
      await showSaveToListSheet(context, spotId);
      return;
    }
    final l = AppLocalizations.of(context);
    try {
      await controller.saveToFavourites();
    } catch (_) {
      if (context.mounted) _showNotice(context, l.errorGeneric);
      return;
    }
    if (!context.mounted) return;
    // from the root navigator: this button can be gone by the time it is used
    final root = Navigator.of(context, rootNavigator: true);
    _showNotice(
      context,
      l.savedToFavourites,
      actionLabel: l.savedChangeList,
      onAction: () => showSaveToListSheet(root.context, spotId),
    );
  }

  void _longPress(BuildContext context, WidgetRef ref) {
    if (!_needsLogin(context, ref)) showSaveToListSheet(context, spotId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final saved = ref.watch(spotSavedProvider(spotId)).value?.isNotEmpty;
    final isSaved = saved ?? false;
    final icon = Icon(isSaved ? Icons.bookmark : Icons.bookmark_border);
    final label = isSaved ? l.saved : l.save;
    if (iconOnly) {
      return IconButton(
        key: const Key('saveSpot'),
        tooltip: label,
        color: color,
        icon: icon,
        onPressed: () => _tap(context, ref),
        onLongPress: () => _longPress(context, ref),
      );
    }
    return FilledButton.tonalIcon(
      key: const Key('saveSpot'),
      onPressed: () => _tap(context, ref),
      onLongPress: () => _longPress(context, ref),
      icon: icon,
      label: Text(label),
    );
  }
}

/// A snackbar shows in the nearest Scaffold, which for a card in a modal
/// sheet is the page behind the sheet, covered by it. There the notice goes
/// above everything instead.
void _showNotice(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  if (Scaffold.maybeOf(context) == null) {
    _OverlayNotice.show(context, message, actionLabel, onAction);
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: kSavedNoticeDuration,
        // one with an action would stay until dismissed
        persist: false,
        action: actionLabel == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction!),
      ),
    );
}

/// Looks like a floating snackbar, in the root overlay.
class _OverlayNotice {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void _hide() {
    _timer?.cancel();
    _timer = null;
    if (_entry?.mounted ?? false) _entry!.remove();
    _entry = null;
  }

  static void show(
    BuildContext context,
    String message,
    String? actionLabel,
    VoidCallback? onAction,
  ) {
    _hide();
    final entry = OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final text = scheme.onInverseSurface;
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
                child: Material(
                  key: const Key('savedNotice'),
                  color: scheme.inverseSurface,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              message,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: text,
                              ),
                            ),
                          ),
                        ),
                        if (actionLabel != null)
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: scheme.inversePrimary,
                            ),
                            onPressed: () {
                              _hide();
                              onAction?.call();
                            },
                            child: Text(actionLabel),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    _entry = entry;
    _timer = Timer(kSavedNoticeDuration, _hide);
    Overlay.of(context, rootOverlay: true).insert(entry);
  }
}
