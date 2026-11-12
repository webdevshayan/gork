import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gork/app.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Blocks raw Image.network calls so the glass shell uses its offline
/// fallbacks — keeps these tests deterministic.
class _BlockedOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _BlockedClient();
}

class _BlockedClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('network disabled in widget tests');
}

void main() {
  setUpAll(() {
    HttpOverrides.global = _BlockedOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
      // Fail-fast weather: no real sockets, no pending timeout timers.
      httpClient: MockClient((request) async => http.Response('offline', 500)),
    );
  });

  testWidgets('first launch shows onboarding, not home', (tester) async {
    await tester.pumpWidget(const GorkApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('Bring your own key'), findsOneWidget);
    expect(find.text('Shayan Ali Jalb'), findsNothing);
  });

  testWidgets('walking through the pages sets the flag and lands on home', (
    tester,
  ) async {
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

    expect(find.text('Sehwan Taluka, PK'), findsOneWidget,
        reason: 'home now leads with the weather card');
    expect(find.text('Message Hark'), findsOneWidget);
    expect(Locator.prefs.getBool('onboarding.done'), isTrue);
  });

  testWidgets('second launch goes straight to home', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    Locator.reset();
    Locator.bind(prefs: await SharedPreferences.getInstance());

    await tester.pumpWidget(const GorkApp());
    await tester.pumpAndSettle();

    expect(find.text('Sehwan Taluka, PK'), findsOneWidget);
    expect(find.text('Start using gork'), findsNothing);
  });
}
