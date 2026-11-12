import 'package:flutter_test/flutter_test.dart';
import 'package:gork/app.dart';
import 'package:gork/services/locator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(prefs: await SharedPreferences.getInstance());
  });

  testWidgets('first launch shows onboarding, not home', (tester) async {
    await tester.pumpWidget(const GorkApp());
    await tester.pumpAndSettle();

    expect(
        find.textContaining('Bring your own key'), findsOneWidget);
    expect(find.text('gork: your personal AI assistant'), findsNothing);
  });

  testWidgets('walking through the pages sets the flag and lands on home',
      (tester) async {
    await tester.pumpWidget(const GorkApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Connect a provider'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('You are set'), findsOneWidget);

    await tester.tap(find.text('Start using gork'));
    await tester.pumpAndSettle();

    expect(find.text('gork: your personal AI assistant'), findsOneWidget);
    expect(Locator.prefs.getBool('onboarding.done'), isTrue);
  });

  testWidgets('second launch goes straight to home', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    Locator.reset();
    Locator.bind(prefs: await SharedPreferences.getInstance());

    await tester.pumpWidget(const GorkApp());
    await tester.pumpAndSettle();

    expect(find.text('gork: your personal AI assistant'), findsOneWidget);
    expect(find.text('Start using gork'), findsNothing);
  });
}
