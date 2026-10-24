import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Placeholder, replaced by Task 8.
class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context).mapTitle)),
      );
}
