import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gork/services/locator.dart';
import 'package:gork/services/panels_store.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/services/tool_registry.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
    );
  });

  test('remember + list_memory affect the real memory store', () async {
    final registry = buildAppToolRegistry();

    final r1 = await registry.execute('remember', {'fact': 'likes tea'});
    expect(r1, 'remembered: likes tea');
    expect(Locator.memory.all(), ['likes tea']);

    final r2 = await registry.execute('list_memory', {});
    expect(r2, contains('likes tea'));
  });

  test('create_project, create_task, create_panel, save_vault_entry', () async {
    final registry = buildAppToolRegistry();

    await registry.execute('create_project', {'title': 'Move flat', 'notes': 'list'});
    expect(Locator.projects.all().single.title, 'Move flat');

    await registry.execute('create_task', {
      'title': 'News',
      'prompt': 'summarize news',
      'repeatMinutes': 120
    });
    expect(Locator.tasks.all().single.repeatMinutes, 120);

    await registry.execute('create_panel', {'title': 'Water', 'value': '6/8'});
    expect(Locator.panels.all().any((p) => p.title == 'Water'), isTrue);

    await registry.execute('save_vault_entry', {'title': 'Mail', 'secret': 'pw'});
    expect(await Locator.vault.all().then((e) => e.single.secret), 'pw');
  });

  test('unknown tool and empty args return safe error text', () async {
    final registry = buildAppToolRegistry();
    expect(await registry.execute('nope', {}), contains('unknown tool'));
    expect(await registry.execute('remember', {'fact': '  '}), contains('error'));
  });

  test('panel created via tool shows on Panels screen data', () async {
    final registry = buildAppToolRegistry();
    await registry.execute('create_panel', {'title': 'From agent'});
    final panels = Locator.panels.all();
    expect(panels.map((p) => p.title), contains('From agent'));
    expect(panels.first.source, PanelSource.weather); // seeded panel intact
  });
}
