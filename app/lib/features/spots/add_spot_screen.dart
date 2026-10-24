import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Placeholder, replaced by Task 9.
class AddSpotScreen extends StatelessWidget {
  const AddSpotScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context).addSpotTitle)),
      );
}
