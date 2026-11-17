import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gork/widgets/error_card.dart';

/// The chat error surface: one human line, raw provider JSON only behind
/// the Details expander.
void main() {
  testWidgets('shows the summary; the raw details stay hidden until '
      'expanded, and collapse again', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ErrorDetailsCard(
          summary: 'HTTP 402: This request requires more credits.',
          details: '{"error":{"metadata":{"previous_errors":[1,2,3]}}}',
        ),
      ),
    ));

    expect(find.textContaining('more credits'), findsOneWidget);
    expect(find.textContaining('previous_errors'), findsNothing,
        reason: 'the raw body is not even built while collapsed');

    await tester.tap(find.byKey(const ValueKey('error-details-toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('previous_errors'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('error-details-toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('previous_errors'), findsNothing);
  });

  testWidgets('no details means no expander at all', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ErrorDetailsCard(summary: 'Connection timed out after 15 s.'),
      ),
    ));

    expect(find.textContaining('Connection timed out'), findsOneWidget);
    expect(find.byKey(const ValueKey('error-details-toggle')), findsNothing);
  });
}
