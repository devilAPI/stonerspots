import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Placeholder, replaced by Task 9. Constructed by the router as
/// `SpotDetailScreen(spotId: id)`.
class SpotDetailScreen extends StatelessWidget {
  const SpotDetailScreen({super.key, required this.spotId});

  final int spotId;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context).spotDetailTitle)),
      );
}
