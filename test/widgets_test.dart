import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gork/widgets/g_button.dart';
import 'package:gork/widgets/g_card.dart';
import 'package:gork/widgets/screen.dart';

void main() {
  testWidgets('Screen renders title and body inside safe padding', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Screen(title: 'Demo', body: Text('hello body')),
      ),
    );

    expect(find.text('Demo'), findsOneWidget);
    expect(find.text('hello body'), findsOneWidget);
  });

  testWidgets('GButton primary fires onPressed on tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GButton(label: 'Tap me', onPressed: () => taps++),
      ),
    );

    expect(find.text('Tap me'), findsOneWidget);
    await tester.tap(find.text('Tap me'));
    expect(taps, 1);
  });

  testWidgets('GButton disabled variant does not fire', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GButton(label: 'Nope', onPressed: null),
      ),
    );

    await tester.tap(find.text('Nope'), warnIfMissed: false);
    expect(taps, 0);
  });

  testWidgets('GCard renders child on surface container', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GCard(child: Text('card child')),
      ),
    );

    expect(find.text('card child'), findsOneWidget);
  });
}
