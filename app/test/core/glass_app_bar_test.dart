import 'package:app/core/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('contentTop clears the bar from inside a page body too', (
    t,
  ) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1;
    t.view.padding = const FakeViewPadding(top: 48);
    t.view.viewPadding = const FakeViewPadding(top: 48);
    addTearDown(t.view.reset);
    late double fromBody;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: GlassAppBar(
            title: const Text('Title'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {},
            ),
          ),
          body: Builder(
            builder: (context) {
              fromBody = GlassAppBar.contentTop(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    final bar = t.getRect(find.byType(GlassControls));
    expect(fromBody, greaterThanOrEqualTo(bar.bottom));
  });

  testWidgets('back is round, actions share one capsule', (t) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(visualDensity: VisualDensity.standard),
        home: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: GlassAppBar(
            title: const Text('Title'),
            leading: IconButton(
              key: const Key('back'),
              icon: const Icon(Icons.arrow_back),
              onPressed: () {},
            ),
            actions: [
              IconButton(
                key: const Key('share'),
                icon: const Icon(Icons.share),
                onPressed: () {},
              ),
              IconButton(
                key: const Key('more'),
                icon: const Icon(Icons.more_horiz),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
    final controls = find.byType(GlassControls);
    expect(controls, findsNWidgets(2));
    final back = t.getRect(controls.first);
    expect(back.width, closeTo(back.height, 0.5)); // a circle
    final group = t.getRect(controls.last);
    expect(group.width, greaterThan(group.height * 1.5)); // a pill
    expect(
      find.descendant(
        of: controls.last,
        matching: find.byKey(const Key('more')),
      ),
      findsOneWidget,
    );
    // the title is plain text between them, centred
    final title = t.getCenter(find.text('Title'));
    expect(title.dx, closeTo(200, 30));
  });
}
