import 'package:flutter_test/flutter_test.dart';
import 'package:gork/app.dart';
import 'package:gork/services/locator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    Locator.reset();
    Locator.bind(prefs: await SharedPreferences.getInstance());
  });

  testWidgets('app builds and shows its name and purpose', (tester) async {
    await tester.pumpWidget(const GorkApp());
    await tester.pumpAndSettle();

    expect(find.text('gork'), findsOneWidget);
    expect(find.text('gork: your personal AI assistant'), findsOneWidget);
  });
}
