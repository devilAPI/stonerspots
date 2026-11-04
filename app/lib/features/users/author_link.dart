import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/user_avatar.dart';
import '../../l10n/app_localizations.dart';

/// The path of a user's public profile.
String userPath(int id) => '/user/$id';

/// Marks a subtree as the profile page of [userId]: author links to that
/// user show as plain text there instead of opening the same page again.
class ProfileScope extends InheritedWidget {
  const ProfileScope({super.key, required this.userId, required super.child});

  final int userId;

  static int? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProfileScope>()?.userId;

  @override
  bool updateShouldNotify(ProfileScope old) => old.userId != userId;
}

/// Profile pictures changed in this session, by user id (null: removed).
/// Loaded lists still carry the old one until they reload; avatars of these
/// users show the new one right away.
final avatarOverridesProvider =
    NotifierProvider<AvatarOverrides, Map<int, String?>>(AvatarOverrides.new);

class AvatarOverrides extends Notifier<Map<int, String?>> {
  @override
  Map<int, String?> build() => const {};

  void set(int userId, String? url) => state = {...state, userId: url};

  /// The picture to show for [userId], whose data came with [loaded].
  static String? resolve(
    Map<int, String?> overrides,
    int userId,
    String? loaded,
  ) => overrides.containsKey(userId) ? overrides[userId] : loaded;
}

/// What tapping an author opens: their profile, unless this is it already.
/// [onTap] replaces the navigation (e.g. to close a sheet first).
VoidCallback? _profileTap(
  BuildContext context,
  int userId,
  void Function(int userId)? onTap,
) {
  if (ProfileScope.of(context) == userId) return null;
  if (onTap != null) return () => onTap(userId);
  return () => context.push(userPath(userId));
}

/// An author's picture that opens their profile.
class AuthorAvatar extends ConsumerWidget {
  const AuthorAvatar({
    super.key,
    required this.author,
    this.radius = 16,
    this.onTap,
  });

  final Author author;
  final double radius;

  /// Replaces opening the profile.
  final void Function(int userId)? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(
      avatarOverridesProvider.select(
        (o) => AvatarOverrides.resolve(o, author.id, author.avatarUrl),
      ),
    );
    return UserAvatar(
      key: Key('authorAvatar-${author.id}'),
      userId: author.id,
      name: author.displayName,
      url: url,
      radius: radius,
      onTap: _profileTap(context, author.id, onTap),
    );
  }
}

/// An author's name that opens their profile; with [avatarRadius] their
/// picture comes first, in the same tap target.
class AuthorLink extends StatelessWidget {
  const AuthorLink({
    super.key,
    required this.author,
    this.label,
    this.style,
    this.avatarRadius,
    this.onTap,
  });

  final Author author;

  /// Shown instead of the name, e.g. "You".
  final String? label;
  final TextStyle? style;
  final double? avatarRadius;

  /// Replaces opening the profile.
  final void Function(int userId)? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label ?? author.displayName,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final radius = avatarRadius;
    // The avatar is shown inside the one tap target, so it is not a button
    // of its own.
    final Widget content = radius == null
        ? text
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: AuthorAvatar(
                  author: author,
                  radius: radius,
                  onTap: (_) {},
                ),
              ),
              SizedBox(width: radius < 14 ? 6 : 8),
              Flexible(child: text),
            ],
          );
    final tap = _profileTap(context, author.id, onTap);
    if (tap == null) {
      return radius == null ? content : IgnorePointer(child: content);
    }
    return InkWell(
      key: Key('authorLink-${author.id}'),
      borderRadius: BorderRadius.circular(radius == null ? 4 : radius + 4),
      onTap: tap,
      // the avatar's own ink stays out of the way: the whole row is one link
      child: radius == null ? content : IgnorePointer(child: content),
    );
  }
}

/// "Added by" with the owner's picture and name, which opens their profile;
/// "Deleted account" when [author] is null.
class SpotOwnerLine extends StatelessWidget {
  const SpotOwnerLine({
    super.key,
    required this.author,
    this.avatarRadius = 12,
    this.style,
    this.onTap,
  });

  final Author? author;
  final double avatarRadius;
  final TextStyle? style;

  /// Replaces opening the profile.
  final void Function(int userId)? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final style = this.style ?? Theme.of(context).textTheme.bodyMedium;
    final author = this.author;
    return Row(
      key: const Key('spotOwner'),
      children: [
        Text(l.spotAddedBy, style: style),
        const SizedBox(width: 6),
        Flexible(
          child: author == null
              ? Row(
                  key: const Key('spotOwnerDeleted'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DeletedAvatar(radius: avatarRadius),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        l.deletedAccount,
                        style: style?.copyWith(fontStyle: FontStyle.italic),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              : AuthorLink(
                  author: author,
                  avatarRadius: avatarRadius,
                  style: style?.copyWith(fontWeight: FontWeight.w600),
                  onTap: onTap,
                ),
        ),
      ],
    );
  }
}
