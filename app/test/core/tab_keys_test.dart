import 'package:app/core/tab_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Tabs extends StatefulWidget {
  const _Tabs();
  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  int index = 0;
  @override
  Widget build(BuildContext context) => TabKeys(
    count: 3,
    index: index,
    onSelect: (i) => setState(() => index = i),
    child: Scaffold(
      body: Column(
        children: [
          Text('tab $index'),
          const TextField(key: Key('field')),
          Builder(
            builder: (c) => TextButton(
              onPressed: () => Navigator.of(c).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('page above')),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _pump(WidgetTester t) async {
  await t.pumpWidget(const MaterialApp(home: _Tabs()));
  await t.pumpAndSettle();
}

Future<void> _ctrlTab(WidgetTester t, {bool shift = false}) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.tab);
  if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pump();
}

void main() {
  testWidgets('digits pick a tab, with nothing focused', (t) async {
    await _pump(t);
    await t.sendKeyEvent(LogicalKeyboardKey.digit3);
    await t.pump();
    expect(find.text('tab 2'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.digit1);
    await t.pump();
    expect(find.text('tab 0'), findsOneWidget);
    // more digits than tabs: ignored
    await t.sendKeyEvent(LogicalKeyboardKey.digit5);
    await t.pump();
    expect(find.text('tab 0'), findsOneWidget);
  });

  testWidgets('Ctrl+Tab / Ctrl+Shift+Tab go round', (t) async {
    await _pump(t);
    await _ctrlTab(t);
    expect(find.text('tab 1'), findsOneWidget);
    await _ctrlTab(t, shift: true);
    await _ctrlTab(t, shift: true);
    expect(find.text('tab 2'), findsOneWidget); // wrapped
    await _ctrlTab(t);
    expect(find.text('tab 0'), findsOneWidget);
  });

  testWidgets('while typing, digits go into the field', (t) async {
    await _pump(t);
    await t.tap(find.byKey(const Key('field')));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.digit2);
    await t.pump();
    expect(find.text('tab 0'), findsOneWidget);
    await _ctrlTab(t);
    expect(find.text('tab 0'), findsOneWidget);
  });

  testWidgets('a page above the tabs keeps its keys', (t) async {
    await _pump(t);
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.digit2);
    await t.pump();
    Navigator.of(t.element(find.text('page above'))).pop();
    await t.pumpAndSettle();
    expect(find.text('tab 0'), findsOneWidget);
  });
}
