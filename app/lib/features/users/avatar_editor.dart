import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/glass.dart';
import '../../core/user_avatar.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_controller.dart';
import '../spots/add_spot_errors.dart';
import 'author_link.dart';
import 'avatar_repository.dart';
import 'users_controller.dart';

enum _AvatarAction { choose, remove }

/// Your own profile picture with a camera badge: tapping it offers to choose
/// a new one or remove it. While it uploads, a spinner sits on it.
class OwnAvatarEditor extends ConsumerStatefulWidget {
  const OwnAvatarEditor({
    super.key,
    required this.userId,
    required this.name,
    required this.url,
    this.radius = 28,
  });

  final int userId;
  final String name;

  /// The picture as loaded with the profile.
  final String? url;
  final double radius;

  @override
  ConsumerState<OwnAvatarEditor> createState() => _OwnAvatarEditorState();
}

class _OwnAvatarEditorState extends ConsumerState<OwnAvatarEditor> {
  bool _busy = false;

  /// Upload progress 0..1; null while it cannot be told (compressing,
  /// removing).
  double? _progress;

  String? get _current => AvatarOverrides.resolve(
    ref.read(avatarOverridesProvider),
    widget.userId,
    widget.url,
  );

  Future<void> _open() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final hasPhoto = _current != null;
    final action = await showGlassSheet<_AvatarAction>(
      context: context,
      radius: 32,
      useRootNavigator: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheet) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const Key('avatarChoose'),
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(l.avatarChoose),
                onTap: () => Navigator.pop(sheet, _AvatarAction.choose),
              ),
              if (hasPhoto)
                ListTile(
                  key: const Key('avatarRemove'),
                  leading: const Icon(Icons.delete_outline),
                  title: Text(l.avatarRemove),
                  onTap: () => Navigator.pop(sheet, _AvatarAction.remove),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _AvatarAction.choose:
        await _choose();
      case _AvatarAction.remove:
        await _run(() async {
          await ref.read(avatarRepositoryProvider).remove();
          return null;
        });
    }
  }

  Future<void> _choose() async {
    final file = await ref.read(avatarPickerProvider)();
    if (file == null || !mounted) return;
    await _run(
      () => ref
          .read(avatarRepositoryProvider)
          .upload(
            file,
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          ),
    );
  }

  /// Runs the change, then shows its result everywhere: the session's user,
  /// avatars already on screen, and this profile once reloaded.
  Future<void> _run(Future<String?> Function() change) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _progress = null;
    });
    try {
      final url = await change();
      if (!mounted) return;
      ref.read(authControllerProvider.notifier).setAvatarUrl(url);
      ref.read(avatarOverridesProvider.notifier).set(widget.userId, url);
      ref.invalidate(userProfileProvider(widget.userId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(addSpotErrorText(l, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final url = ref.watch(
      avatarOverridesProvider.select(
        (o) => AvatarOverrides.resolve(o, widget.userId, widget.url),
      ),
    );
    final r = widget.radius;
    final badge = (r * 0.5).clamp(18.0, 26.0);
    return Tooltip(
      message: l.avatarChange,
      child: SizedBox.square(
        dimension: r * 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            UserAvatar(
              key: const Key('ownAvatar'),
              userId: widget.userId,
              name: widget.name,
              url: url,
              radius: r,
              onTap: _busy ? null : _open,
            ),
            if (_busy)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(r * 0.35),
                      child: CircularProgressIndicator(
                        key: const Key('avatarProgress'),
                        value: _progress,
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: -2,
              bottom: -2,
              child: IgnorePointer(
                child: Container(
                  key: const Key('avatarCameraBadge'),
                  width: badge,
                  height: badge,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.photo_camera,
                    size: badge * 0.55,
                    color: scheme.onPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
