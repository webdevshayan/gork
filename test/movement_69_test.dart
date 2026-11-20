import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/constants/design_tokens.dart';
import 'package:gork/screens/gork_home.dart';
import 'package:gork/screens/menu_screen.dart';
import 'package:gork/screens/theme_preferences_screen.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/panels_store.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/services/skills_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 69 — the big de-slop: connections, skills, AI-authored panels,
/// quoted replies, server backups, instant home. The guards that keep it.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
    );
  });

  group('PanelSpec.fromAgent — the AI authors widgets, never a form', () {
    test('a graph spec resolves to graph when a series is present', () {
      final spec = PanelSpec.fromAgent({
        'title': 'Study streak',
        'kind': 'graph',
        'series': [3, 5, 4, 8, 9],
        'note': 'days in a row',
      });
      expect(spec.kind, PanelKind.graph);
      expect(spec.series, [3, 5, 4, 8, 9]);
      expect(spec.source, PanelSource.agent);
      expect(spec.id, startsWith('agent-'));
    });

    test('progress / list / stat resolve honestly', () {
      final progress = PanelSpec.fromAgent(
          {'title': 'Thesis', 'kind': 'progress', 'progress': 0.42});
      expect(progress.kind, PanelKind.progress);
      expect(progress.progress, closeTo(0.42, 0.001));

      final list = PanelSpec.fromAgent({
        'title': 'Topics to read',
        'kind': 'list',
        'items': ['kubernetes', 'river pods'],
      });
      expect(list.kind, PanelKind.list);
      expect(list.items.length, 2);

      final stat = PanelSpec.fromAgent(
          {'title': 'Shipped PRs', 'kind': 'stat', 'value': '12'});
      expect(stat.kind, PanelKind.metric);
      expect(stat.manualValue, '12');
    });

    test('a series-less graph degrades to a stat — never a broken widget',
        () {
      final spec =
          PanelSpec.fromAgent({'title': 'Empty', 'kind': 'graph'});
      expect(spec.kind, PanelKind.metric);
    });

    test('addSpec puts the new panel right under the weather panel', () async {
      final spec =
          PanelSpec.fromAgent({'title': 'Water the plants', 'value': '3'});
      await Locator.panels.addSpec(spec);
      final all = Locator.panels.all();
      expect(all.first.id, 'weather-now');
      expect(all[1].title, 'Water the plants');
    });
  });

  group('SkillsStore — markdown how-tos the agent follows', () {
    test('save + read round-trip (prefs fallback works in tests)', () async {
      final skill = await Locator.skills.save(
          title: 'Weekly backup', body: '1. ssh in\n2. run gork-backup\n');
      expect(skill.title, 'Weekly backup');
      final all = await Locator.skills.all();
      expect(all.any((s) => s.id == skill.id), isTrue);
      final md = await Locator.skills.read(skill.id);
      expect(md, contains('# Weekly backup'));
    });

    test('delete removes the skill', () async {
      final skill = await Locator.skills.save(title: 'Temp', body: 'x');
      await Locator.skills.delete(skill.id);
      final all = await Locator.skills.all();
      expect(all.any((s) => s.id == skill.id), isFalse);
    });

    test('addFromAgent ignores malformed blocks', () async {
      final bad = await Locator.skills.addFromAgent({'title': ''});
      expect(bad, isNull);
      final ok = await Locator.skills
          .addFromAgent({'title': 'Inbox zero', 'steps': '1. triage\n'});
      expect(ok, isNotNull);
      expect(ok!.title, 'Inbox zero');
    });
  });

  group('Outbox — identity headers + full-history backup', () {
    testWidgets('every request carries the device id and the account',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'vps.url': 'http://vps.test',
        'profile.email': 'shayan@example.com',
      });
      Locator.reset();
      final seenHeaders = <String, String>{};
      Locator.bind(
        prefs: await SharedPreferences.getInstance(),
        store: InMemorySecureStore(),
        httpClient: MockClient((request) async {
          seenHeaders.addAll(request.headers);
          if (request.url.path.endsWith('/v1/backup')) {
            return http.Response(jsonEncode({'ok': true}), 201);
          }
          return http.Response(jsonEncode({'id': 'job1'}), 201);
        }),
      );
      final ok = await Locator.outbox.pushBackup();
      expect(ok, isTrue);
      expect(seenHeaders['X-Gork-Device'], isNotEmpty);
      expect(seenHeaders['X-Gork-Account'], 'shayan@example.com');
      // The same device id is minted once and reused.
      final again = await Locator.outbox.deviceId();
      expect(again, seenHeaders['X-Gork-Device']);
    });

    test('pullBackup returns the stored conversations when found', () async {
      SharedPreferences.setMockInitialValues({
        'vps.url': 'http://vps.test',
        'profile.email': 'shayan@example.com',
      });
      Locator.reset();
      Locator.bind(
        prefs: await SharedPreferences.getInstance(),
        store: InMemorySecureStore(),
        httpClient: MockClient((request) async {
          return http.Response(
              jsonEncode({
                'found': true,
                'conversations': [
                  {
                    'id': 'global',
                    'title': 'Chat',
                    'messages': [
                      {'role': 'user', 'content': 'hello', 'time': 5}
                    ],
                  }
                ],
              }),
              200);
        }),
      );
      final result = await Locator.outbox.pullBackup();
      expect(result, isNotNull);
      expect(result!.first['id'], 'global');
    });
  });

  group('The menu is de-slopped — connections, skills, sticky search', () {
    testWidgets('one flat list: no Inbox, no Accounts, no Integrations, '
        'no duplicate Google row', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MenuScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Connections'), findsOneWidget);
      expect(find.text('Skills'), findsOneWidget);
      expect(find.text('Inbox'), findsNothing);
      expect(find.text('Accounts'), findsNothing);
      expect(find.text('Integrations'), findsNothing);
      expect(find.text('Google'), findsNothing);
    });

    testWidgets('the search bar is sticky and digs DEEP', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MenuScreen()));
      await tester.pumpAndSettle();

      // Type something that only exists INSIDE another screen — the deep
      // index matches it instantly.
      await tester.enterText(
          find.byKey(const ValueKey('menu-settings-search')), 'gmail');
      await tester.pumpAndSettle();

      expect(find.textContaining('Gmail'), findsWidgets,
          reason: 'gmail is a connection INSIDE the Connections screen');
      // Jump away: the result row pushes the screen and clears the query.
      await tester.tap(find.text('Google setup').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-settings-search')),
          findsNothing,
          reason: 'a jumped-to screen has no menu search bar');
    });
  });

  group('Theme screen — radio rows, not chips', () {
    testWidgets('three radio rows pick and persist', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: ThemePreferencesScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('theme-auto')), findsOneWidget);
      expect(find.byKey(const ValueKey('theme-light')), findsOneWidget);
      expect(find.byKey(const ValueKey('theme-dark')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('theme-dark')));
      await tester.pumpAndSettle();
      expect(Locator.prefs.getString('ui.theme'), 'dark');
    });
  });

  group('The instant home — temperature and clock never wait', () {
    testWidgets('the clock renders on the FIRST frame from the real clock',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      Locator.reset();
      Locator.bind(
        prefs: await SharedPreferences.getInstance(),
        store: InMemorySecureStore(),
      );
      await tester.pumpWidget(const MaterialApp(home: GorkHome()));
      // No pumpAndSettle: the very first frame already carries the clock.
      expect(find.byKey(const ValueKey('home-clock')), findsOneWidget);
      expect(find.text('26°C'), findsNothing,
          reason: 'no fake placeholder temperature ever');
    });
  });
}
