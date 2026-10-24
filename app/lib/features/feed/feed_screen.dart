import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Placeholder, replaced by Task 10.
class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context).feedTitle)),
      );
}
