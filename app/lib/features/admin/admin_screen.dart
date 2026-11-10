import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/back_or_home.dart';
import '../../core/tab_keys.dart';
import '../../l10n/app_localizations.dart';
import 'admin_controller.dart';
import 'admin_reports_tab.dart';
import 'admin_spots_tab.dart';
import 'admin_system_tab.dart';
import 'admin_tags_tab.dart';
import 'admin_users_tab.dart';

/// Moderation page for admins: reports, users, spots, the tag catalog and
/// server actions (backend updates).
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Keep the (auto-disposed) list states alive while the page is open, so
    // switching tabs does not drop searches or loaded pages.
    ref.listen(adminReportsProvider, (_, _) {});
    ref.listen(adminUsersProvider, (_, _) {});
    ref.listen(adminSpotsProvider, (_, _) {});
    return DefaultTabController(
      length: 5,
      child: Builder(
        // the controller only exists below DefaultTabController
        builder: (context) {
          final tabs = DefaultTabController.of(context);
          return ListenableBuilder(
            listenable: tabs,
            builder: (context, child) => TabKeys(
              count: 5,
              index: tabs.index,
              onSelect: tabs.animateTo,
              child: child!,
            ),
            child: Scaffold(
              appBar: AppBar(
                leading: const BackOrHomeButton(),
                title: Text(l10n.adminTitle),
                bottom: TabBar(
                  tabs: [
                    Tab(text: l10n.adminReports),
                    Tab(text: l10n.adminUsers),
                    Tab(text: l10n.adminSpots),
                    Tab(text: l10n.adminTags),
                    Tab(text: l10n.adminActions),
                  ],
                ),
              ),
              body: const TabBarView(
                children: [
                  AdminReportsTab(),
                  AdminUsersTab(),
                  AdminSpotsTab(),
                  AdminTagsTab(),
                  AdminSystemTab(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
