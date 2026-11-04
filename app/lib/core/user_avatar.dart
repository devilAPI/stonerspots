import 'package:flutter/material.dart';

import 'net_photo.dart';

/// The background of a user's initial: a hue picked from their id, so people
/// without a picture still look different from each other.
Color avatarColor(int userId) {
  // golden angle: neighbouring ids get far-apart hues
  final hue = (userId * 137.508) % 360;
  return HSLColor.fromAHSL(1, hue, 0.45, 0.38).toColor();
}

/// The first letter of [name], upper case; "?" for an empty name.
String avatarInitial(String name) {
  final t = name.trim();
  return t.isEmpty ? '?' : t.characters.first.toUpperCase();
}

/// A user's profile picture in a circle of [radius]. Without one (or while
/// it loads, or when it cannot be loaded) it shows their initial on a colour
/// of their own. With [onTap] it is a button.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.userId,
    required this.name,
    this.url,
    this.radius = 20,
    this.onTap,
  });

  final int userId;
  final String name;
  final String? url;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final initial = _Initial(userId: userId, name: name, radius: radius);
    final url = this.url;
    Widget avatar = SizedBox.square(
      dimension: radius * 2,
      child: ClipOval(
        child: url == null
            ? initial
            : NetPhoto(
                url,
                key: const Key('userAvatarPhoto'),
                decodeWidth: radius * 2,
                fallback: initial,
              ),
      ),
    );
    final onTap = this.onTap;
    if (onTap != null) {
      avatar = Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: avatar,
        ),
      );
    }
    return Semantics(
      label: name,
      button: onTap != null,
      excludeSemantics: true,
      child: avatar,
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial({
    required this.userId,
    required this.name,
    required this.radius,
  });

  final int userId;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const Key('userAvatarInitial'),
    color: avatarColor(userId),
    child: Center(
      child: Text(
        avatarInitial(name),
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.9,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    ),
  );
}

/// The avatar of an account that no longer exists: a grey circle.
class DeletedAvatar extends StatelessWidget {
  const DeletedAvatar({super.key, this.radius = 20});

  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: Colors.grey.withValues(alpha: 0.35),
    child: Icon(
      Icons.person_off_outlined,
      size: radius * 1.1,
      color: Colors.white70,
    ),
  );
}
