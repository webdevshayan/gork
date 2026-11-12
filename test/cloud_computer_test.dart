import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gork/screens/cloud_computer_screen.dart';
import 'package:gork/services/cloud_computer_store.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
    );
  });

  test('config round-trip and backend rules', () async {
    final store = Locator.cloudComputer;
    final loaded = store.load();
    expect(loaded.backend, CloudBackend.agentvps); // default
    expect(loaded.isConfigured, isFalse);

    await store.save(loaded.copyWith(
        endpoint: 'http://1.2.3.4:8787',
        apiKey: 'k',
        updatedAt: 123));
    final saved = store.load();
    expect(saved.endpoint, 'http://1.2.3.4:8787');
    expect(saved.isConfigured, isTrue);

    // browseruse needs key but not endpoint.
    final bu = CloudComputerConfig(
        backend: CloudBackend.browseruse, endpoint: '', apiKey: '', updatedAt: 0);
    expect(bu.needsEndpoint, isFalse);
    expect(bu.needsApiKey, isTrue);
    expect(bu.isConfigured, isFalse);

    // openbrowse needs endpoint but not key.
    final ob = CloudComputerConfig(
        backend: CloudBackend.openbrowse, endpoint: '', apiKey: '', updatedAt: 0);
    expect(ob.needsEndpoint, isTrue);
    expect(ob.needsApiKey, isFalse);
  });

  test('pingCloudComputer checks /health', () async {
    final okClient = MockClient((request) async {
      expect(request.url.toString(), endsWith('/health'));
      return http.Response('{"status":"ok"}', 200);
    });
    final config = CloudComputerConfig(
        backend: CloudBackend.agentvps,
        endpoint: 'http://1.2.3.4:8787',
        apiKey: '',
        updatedAt: 0);
    expect(await pingCloudComputer(config, okClient), isNull);

    final failClient = MockClient((request) async => http.Response('', 500));
    expect(await pingCloudComputer(config, failClient), 'HTTP 500');

    expect(
        await pingCloudComputer(
            config.copyWith(endpoint: ''), okClient),
        'No endpoint saved.');
  });

  testWidgets('screen renders all three backends and saves config',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: CloudComputerScreen()));
    await tester.pumpAndSettle();

    expect(find.text('AgentVPS (self-hosted)'), findsOneWidget);
    expect(find.text('Browser Use Cloud'), findsOneWidget);
    expect(find.text('openbrowse (self-hosted)'), findsOneWidget);

    // Scroll down to the install command card (ListView builds lazily).
    await tester.scrollUntilVisible(
      find.textContaining('curl -fsSL'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('curl -fsSL'), findsOneWidget);

    // Scroll back up to the endpoint field, type the endpoint.
    await tester.scrollUntilVisible(
      find.byKey(const Key('cloud-endpoint')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('cloud-endpoint')), 'http://9.9.9.9:8787');
    await tester.pumpAndSettle();

    // Scroll down to Save and tap; the controller keeps the typed text.
    await tester.scrollUntilVisible(
      find.text('Save'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = Locator.cloudComputer.load();
    expect(saved.endpoint, 'http://9.9.9.9:8787');
    expect(saved.backend, CloudBackend.agentvps);
  });
}
