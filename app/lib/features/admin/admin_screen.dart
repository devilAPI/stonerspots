import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/glass.dart';
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
              extendBodyBehindAppBar: true,
              appBar: GlassAppBar(
                leading: const BackOrHomeButton(),
                title: Text(l10n.adminTitle),
              ),
              body: Column(
                children: [
                  // the sections as one row of glass, under the controls
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      GlassAppBar.contentTop(context),
                      12,
                      8,
                    ),
                    child: GlassTabs(
                      tabs: [
                        Tab(text: l10n.adminReports),
                        Tab(text: l10n.adminUsers),
                        Tab(text: l10n.adminSpots),
                        Tab(text: l10n.adminTags),
                        Tab(text: l10n.adminActions),
                      ],
                    ),
                  ),
                  // the lists fade out under the tabs instead of ending
                  // at a hard edge
                  Expanded(
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (bounds) => LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: const [Color(0x00000000), Color(0xFF000000)],
                        stops: [
                          0,
                          16 / bounds.height.clamp(16, double.infinity),
                        ],
                      ).createShader(bounds),
                      child: const TabBarView(
                        children: [
                          AdminReportsTab(),
                          AdminUsersTab(),
                          AdminSpotsTab(),
                          AdminTagsTab(),
                          AdminSystemTab(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
