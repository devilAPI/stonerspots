import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';

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

/// An author's name that opens their profile.
class AuthorLink extends StatelessWidget {
  const AuthorLink({super.key, required this.author, this.label, this.style});

  final Author author;

  /// Shown instead of the name, e.g. "You".
  final String? label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label ?? author.displayName,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (ProfileScope.of(context) == author.id) return text;
    return InkWell(
      key: Key('authorLink-${author.id}'),
      borderRadius: BorderRadius.circular(4),
      onTap: () => context.push(userPath(author.id)),
      child: text,
    );
  }
}
