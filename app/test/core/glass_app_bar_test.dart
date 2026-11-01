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
          appBar: const GlassAppBar(title: Text('Title')),
          body: Builder(
            builder: (context) {
              fromBody = GlassAppBar.contentTop(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    final bar = t.getRect(find.byType(GlassSurface));
    expect(fromBody, greaterThanOrEqualTo(bar.bottom));
  });
}
