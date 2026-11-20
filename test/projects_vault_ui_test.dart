import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gork/screens/projects_screen.dart';
import 'package:gork/screens/security_screen.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/services/vault_store.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
    );
  });

  testWidgets('create a project with notes and a file', (tester) async {
    // Movement 68 — the editor sheet grew (48dp buttons): give the probe a
    // real phone-sized surface so every hit-test lands like on a device.
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ProjectsScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('No projects yet'), findsOneWidget);

    // Create project — the glass empty state opens the shared editor sheet.
    await tester.tap(find.byKey(const ValueKey('create-project')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Project name').first,
        'Debian setup');
    await tester.enterText(find.widgetWithText(TextField, 'Notes…').first,
        'Steps for the new laptop');
    await tester.tap(find.text('Save project'));
    await tester.pumpAndSettle();

    expect(find.text('Debian setup'), findsOneWidget);
    // Movement 68 — the type grew one size and the card sits lower: the
    // counts line can fall past the lazy-viewport fold. The card EXISTS
    // (title visible right above it) — assert offstage-inclusive.
    expect(
        find.text('0 chats · 0 files · 0 images', skipOffstage: false),
        findsOneWidget,
        reason: 'the unified folder card carries the counts line');

    // Open detail and add a file.
    await tester.tap(find.text('Debian setup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add file'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'notes.md').first, 'install.md');
    await tester.enterText(
        find.widgetWithText(TextField, 'File content…').first, 'apt install git');
    await tester.tap(find.text('Save file'));
    await tester.pumpAndSettle();

    expect(find.text('install.md'), findsOneWidget);
    expect(Locator.projects.byId(
        Locator.projects.all().first.id)!.files.first.content,
        'apt install git');
  });

  testWidgets('security screen lists vault entries but never the secret',
      (tester) async {
    // Movement 50: the wallet feature is removed; the vault is shown on the
    // Security screen — by name and username only, the secret never renders.
    await Locator.vault.save(const VaultEntry(
      id: 'v1',
      title: 'Mail login',
      username: 'shayanalibuilds@gmail.com',
      secret: 's3cret!',
      notes: '',
      createdAt: 1,
      aiAccess: true,
    ));
    await tester.pumpWidget(const MaterialApp(home: SecurityScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Mail login'), findsOneWidget);
    expect(find.text('shayanalibuilds@gmail.com'), findsOneWidget);
    expect(find.text('s3cret!'), findsNothing,
        reason: 'the secret is never rendered, not even revealed');
    expect(find.text('Reveal'), findsNothing,
        reason: 'there is no reveal path on the security surface');
  });
}
