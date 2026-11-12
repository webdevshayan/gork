import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/widgets/markdown_view.dart';

class _BlockedOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _BlockedClient();
}

class _BlockedClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('network disabled in widget tests');
}

RichText _firstRich(WidgetTester tester) =>
    tester.widget<RichText>(find.byType(RichText).first);

String _flatten(TextSpan span, [String buffer = '']) {
  buffer += span.text ?? '';
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is TextSpan) buffer = _flatten(child, buffer);
  }
  return buffer;
}

/// Looks for a leaf span with [exact] text, testing the EFFECTIVE style
/// (parent styles flow down to children that don't override).
bool _spanWith(TextSpan span, String exact, bool Function(TextStyle?) test,
    [TextStyle? inherited]) {
  final effective = inherited == null
      ? span.style
      : (span.style == null
          ? inherited
          : inherited.merge(span.style));
  if (span.text == exact && test(effective)) return true;
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is TextSpan &&
        _spanWith(child, exact, test, effective)) {
      return true;
    }
  }
  return false;
}

Future<void> pump(WidgetTester tester, String markdown) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: MarkdownView(markdown))),
  ));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(() => HttpOverrides.global = _BlockedOverrides());
  tearDownAll(() => HttpOverrides.global = null);

  testWidgets('headings render with weight and scale', (tester) async {
    await pump(tester, '# Big\n\n## Medium\n\n### Small');
    expect(find.text('Big'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.text('Small'), findsOneWidget);
    final h1 = tester.widget<Text>(find.text('Big'));
    expect(h1.style!.fontWeight, FontWeight.w700);
    expect(h1.style!.fontSize, greaterThan(20));
    final h3 = tester.widget<Text>(find.text('Small'));
    expect(h3.style!.fontSize, lessThan(20));
  });

  testWidgets('bold, italic and strikethrough render as styled spans', (
    tester,
  ) async {
    await pump(tester, 'This is **bold**, *italic*, and ~~gone~~.');
    final root = _firstRich(tester).text as TextSpan;
    expect(_flatten(root).trim(), 'This is bold, italic, and gone.');
    expect(_spanWith(root, 'bold', (s) => s?.fontWeight == FontWeight.w700),
        isTrue, reason: 'bold span');
    expect(
        _spanWith(root, 'italic', (s) => s?.fontStyle == FontStyle.italic),
        isTrue, reason: 'italic span');
    expect(
        _spanWith(
            root, 'gone', (s) => s?.decoration == TextDecoration.lineThrough),
        isTrue, reason: 'strikethrough span');
  });

  testWidgets('lists render bullets and numbers', (tester) async {
    await pump(tester, '- apples\n- pears\n\n1. first\n2. second');
    expect(find.textContaining('apples', findRichText: true), findsOneWidget);
    expect(find.textContaining('pears', findRichText: true), findsOneWidget);
    expect(find.textContaining('1.'), findsOneWidget);
    expect(find.textContaining('second', findRichText: true), findsOneWidget);
  });

  testWidgets('fenced code blocks render monospace', (tester) async {
    await pump(tester, '```dart\nvoid main() { print("hi"); }\n```');
    final code = find.textContaining('void main()');
    expect(code, findsOneWidget);
    final text = tester.widget<SelectableText>(find.ancestor(
      of: code,
      matching: find.byType(SelectableText),
    ));
    expect(text.style!.fontFamily, contains('mono'));
  });

  testWidgets('tables render header and cells', (tester) async {
    await pump(tester, '| Fruit | Color |\n|---|---|\n| kiwi | green |');
    expect(find.text('Fruit'), findsOneWidget);
    expect(find.text('Color'), findsOneWidget);
    expect(find.text('kiwi'), findsOneWidget);
    expect(find.text('green'), findsOneWidget);
  });

  testWidgets('links are styled but never fetched', (tester) async {
    await pump(tester, 'See [the docs](https://example.com/docs) here.');
    final root = _firstRich(tester).text as TextSpan;
    expect(
      _spanWith(root, 'the docs',
          (s) => s?.color != null && s!.color != Colors.black87),
      isTrue,
      reason: 'link text visually distinct',
    );
    expect(find.textContaining('https://example.com/docs'), findsNothing,
        reason: 'raw url is not dumped into the bubble');
  });

  testWidgets('inline code is distinct from body text', (tester) async {
    await pump(tester, 'Run `gork status` now.');
    final root = _firstRich(tester).text as TextSpan;
    expect(
      _spanWith(root, 'gork status', (s) => s?.fontFamily != null),
      isTrue,
      reason: 'inline code gets the monospace family',
    );
  });

  testWidgets('raw HTML is inert: shown as text, never executed', (
    tester,
  ) async {
    await pump(tester, '<script>alert("pwned")</script>\n\nnormal text');
    expect(find.textContaining('normal text', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('alert("pwned")', findRichText: true),
        findsOneWidget, reason: 'script content is inert plain text');
    expect(tester.takeException(), isNull);
    expect(find.byType(HtmlElementView), findsNothing);
  });

  testWidgets('image syntax shows an offline placeholder, no fetch', (
    tester,
  ) async {
    await pump(tester, '![a kitten](https://example.com/kitten.png)');
    expect(find.textContaining('a kitten'), findsOneWidget,
        reason: 'alt text shown; the URL is never fetched');
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blockquotes render quoted', (tester) async {
    await pump(tester, '> stay hungry');
    expect(find.textContaining('stay hungry', findRichText: true),
        findsOneWidget);
  });
}
