import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gork/screens/projects_screen.dart';
import 'package:gork/screens/wallet_screen.dart';
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

  testWidgets('create a project with notes and a file', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProjectsScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('No projects yet'), findsOneWidget);

    // Create project.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Project name').first,
        'Debian setup');
    await tester.enterText(find.widgetWithText(TextField, 'Notes…').first,
        'Steps for the new laptop');
    await tester.tap(find.text('Save project'));
    await tester.pumpAndSettle();

    expect(find.text('Debian setup'), findsOneWidget);
    expect(find.text('0 file(s)'), findsOneWidget);

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

  testWidgets('vault entry: create, hidden by default, reveal, copy',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WalletScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('No wallets yet'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Name (e.g. Metamask, Binance)').first,
        'Mail login');
    await tester.enterText(
        find.widgetWithText(TextField, 'Seed phrase / private key / card number').first,
        's3cret!');
    await tester.tap(find.text('Save wallet'));
    await tester.pumpAndSettle();

    expect(find.text('Mail login'), findsOneWidget);
    expect(find.text('••••••••••••'), findsOneWidget);
    expect(find.text('s3cret!'), findsNothing); // hidden

    await tester.tap(find.text('Reveal'));
    await tester.pumpAndSettle();
    expect(find.text('s3cret!'), findsOneWidget);

    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    expect(find.text('s3cret!'), findsNothing);
  });
}
