import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import '../constants/design_tokens.dart';

/// Safe, offline markdown rendering for assistant bubbles.
///
/// Built directly on the `markdown` parser (CommonMark + GitHub-flavored:
/// tables, strikethrough, autolinks) with a custom widget renderer. There is
/// deliberately NO web view and NO network: raw HTML degrades to inert plain
/// text, and image syntax renders an offline placeholder with its alt text —
/// so no script can ever run and nothing is ever fetched.
class MarkdownView extends StatelessWidget {
  const MarkdownView(this.data, {super.key, this.onLinkTap});

  final String data;

  /// Receives the link target when a link span is tapped (the caller decides
  /// what to do — by default the URL is simply presented, never opened).
  final ValueChanged<String>? onLinkTap;

  static Color get _ink => GlassColors.text;
  static const Color _accent = Color(0xFF0B57D0);

  /// Movement 65 — THE quote bug. The markdown parser HTML-escapes text
  /// nodes (`"` arrives as &quot;, `'` as &#39;), which is right for HTML
  /// output and wrong here: we render WIDGETS, so every entity must come
  /// back as its character — straight, curly and apostrophe quotes
  /// included. &amp; decodes LAST so double escapes stay single.
  static final RegExp _entity =
      RegExp(r'&(quot|#39|lt|gt|amp);');
  static String _unescape(String text) => text.replaceAllMapped(
        _entity,
        (m) => switch (m.group(1)) {
          'quot' => '"',
          '#39' => "'",
          'lt' => '<',
          'gt' => '>',
          _ => '&',
        },
      );

  @override
  Widget build(BuildContext context) {
    // gitHubFlavored (markdown 7.x) already carries tables, strikethrough,
    // autolinks AND the task-list checkbox syntaxes; single newlines in a
    // paragraph survive as literal \n text nodes, which is exactly the
    // chat semantics an AI reply needs.
    final doc = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    final nodes = doc.parse(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final node in nodes) _block(context, node)]
          .whereType<Widget>()
          .toList(),
    );
  }

  // ---- blocks ----------------------------------------------------------------

  Widget _block(BuildContext context, md.Node node) {
    if (node is md.Text) {
      return _paragraph(_inline(context, [node]));
    }
    if (node is! md.Element) return const SizedBox.shrink();

    switch (node.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final level = int.parse(node.tag.substring(1));
        // Movement 65 — headings keep their inline formatting (a `## Buy
        // **milk**` used to flatten to plain text).
        return Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: switch (level) { 1 => 24, 2 => 21, 3 => 19, _ => 17 },
                fontWeight: FontWeight.w700,
                color: _ink,
                height: 1.25,
              ),
              children: _inline(context, node.children ?? []),
            ),
          ),
        );
      case 'p':
        return _paragraph(_inline(context, node.children ?? []));
      case 'ul':
      case 'ol':
        return _list(context, node);
      case 'blockquote':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: GlassColors.textFaint, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final child in node.children ?? <md.Node>[])
                _block(context, child),
            ],
          ),
        );
      case 'pre':
        final code = _unescape(node.children
                ?.whereType<md.Element>()
                .where((e) => e.tag == 'code')
                .map((e) => e.textContent)
                .join() ??
            node.textContent);
        return Container(
          key: const ValueKey('md-codeblock'),
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            code,
            style: TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: ['monospace'],
              fontSize: 13,
              color: _ink,
              height: 1.4,
            ),
          ),
        );
      case 'table':
        return _table(context, node);
      case 'hr':
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Divider(color: GlassColors.textFaint),
        );
      case 'img':
      case 'image':
        // Offline by design: never fetch, show the alt text.
        return _imagePlaceholder(node.attributes['alt'] ?? 'image');
      default:
        // Unknown/HTML-ish block: keep its text, inert.
        final text = _unescape(node.textContent.trim());
        if (text.isEmpty) return const SizedBox.shrink();
        return _paragraph(_inline(context, [md.Text(text)]));
    }
  }

  Widget _paragraph(List<InlineSpan> spans) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        // Text.rich (NOT raw RichText): only Text wires the SelectionArea
        // registrar, so this is what makes every paragraph selectable.
        child: Text.rich(
          TextSpan(
            style: TextStyle(fontSize: 16, color: _ink, height: 1.35),
            children: spans,
          ),
        ),
      );

  Widget _list(BuildContext context, md.Element node) {
    final ordered = node.tag == 'ol';
    // GFM: `start="7"` resumes numbering; task-list items carry a checkbox.
    var index =
        int.tryParse(node.attributes['start'] ?? '') ?? 1;
    final items = node.children ?? <md.Node>[];
    final rows = <Widget>[];
    for (final item in items) {
      if (item is! md.Element || item.tag != 'li') continue;
      final inlineChildren = <md.Node>[...(item.children ?? <md.Node>[])];
      // Task list: the markdown package renders `- [x] done` as an
      // `input[type=checkbox]` element first in the item.
      final taskInput = inlineChildren.isNotEmpty &&
          inlineChildren.first is md.Element &&
          (inlineChildren.first as md.Element).tag == 'input'
          ? inlineChildren.removeAt(0) as md.Element
          : null;
      final marker = taskInput != null
          ? (taskInput.attributes.containsKey('checked') ? '☑' : '☐')
          : ordered
              ? '${index++}.'
              : '•';
      final hasBlocks = inlineChildren
          .whereType<md.Element>()
          .any((e) => e.tag != 'a' && e.tag != 'strong' && e.tag != 'em' &&
              e.tag != 'del' && e.tag != 'code' && e.tag != 'img' &&
              e.tag != 'br' && e.tag != 'em' && e.tag != 'markdown');
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 4, left: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              marker,
              style: TextStyle(fontSize: 16, color: _ink, height: 1.35),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: hasBlocks
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final child in inlineChildren) _block(context, child),
                      ],
                    )
                  : Text.rich(
                      TextSpan(
                        style: TextStyle(
                            fontSize: 16, color: _ink, height: 1.35),
                        children: _inline(context, inlineChildren),
                      ),
                    ),
            ),
          ],
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }

  Widget _table(BuildContext context, md.Element node) {
    final rows = <TableRow>[];
    final spans = <InlineSpan>[];
    for (final section in node.children ?? <md.Node>[]) {
      if (section is! md.Element) continue;
      for (final tr in section.children ?? <md.Node>[]) {
        if (tr is! md.Element || tr.tag != 'tr') continue;
        final cells = <Widget>[];
        final isHeader = section.tag == 'thead';
        for (final cell in tr.children ?? <md.Node>[]) {
          if (cell is! md.Element || (cell.tag != 'td' && cell.tag != 'th')) {
            continue;
          }
          cells.add(Padding(
            padding: const EdgeInsets.all(8),
            // Movement 65 — cells keep inline formatting (bold in a table
            // used to flatten), and they are selectable like everything.
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isHeader ? FontWeight.w700 : FontWeight.w400,
                  color: _ink,
                ),
                children: _inline(context, cell.children ?? []),
              ),
            ),
          ));
        }
        rows.add(TableRow(children: cells));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    // Wide tables scroll sideways inside the bubble instead of overflowing
    // the message column.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.all(color: GlassColors.textFaint),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: const {0: IntrinsicColumnWidth()},
          children: rows,
        ),
      ),
    );
  }

  Widget _imagePlaceholder(String alt) {
    return Container(
      key: const ValueKey('md-image-placeholder'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GlassColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 18, color: GlassColors.textDim),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              alt,
              style: TextStyle(fontSize: 14, color: GlassColors.textDim),
            ),
          ),
        ],
      ),
    );
  }

  // ---- inline spans ------------------------------------------------------------

  List<InlineSpan> _inline(BuildContext context, List<md.Node> nodes) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      final span = _inlineSpan(context, node);
      if (span != null) spans.add(span);
    }
    if (spans.isEmpty) spans.add(const TextSpan(text: ''));
    return spans;
  }

  InlineSpan? _inlineSpan(BuildContext context, md.Node node) {
    if (node is md.Text) {
      return TextSpan(text: _unescape(node.text));
    }
    if (node is md.UnparsedContent) {
      // Raw HTML etc. — inert text, never interpreted.
      return TextSpan(text: _unescape(node.textContent));
    }
    if (node is! md.Element) return null;

    switch (node.tag) {
      case 'strong':
        return TextSpan(
          style: const TextStyle(fontWeight: FontWeight.w700),
          children: _inline(context, node.children ?? []),
        );
      case 'em':
        return TextSpan(
          style: const TextStyle(fontStyle: FontStyle.italic),
          children: _inline(context, node.children ?? []),
        );
      case 'del':
        return TextSpan(
          style: TextStyle(
            decoration: TextDecoration.lineThrough,
            color: GlassColors.textDim,
          ),
          children: _inline(context, node.children ?? []),
        );
      case 'code':
        return TextSpan(
          style: const TextStyle(
            fontFamily: 'monospace',
            fontFamilyFallback: ['monospace'],
            fontSize: 14.5,
            backgroundColor: Color(0x14000000),
          ),
          text: _unescape(node.textContent),
        );
      case 'a':
        final href = node.attributes['href'] ?? '';
        return TextSpan(
          style: const TextStyle(color: _accent, decoration: TextDecoration.underline),
          children: _inline(context, node.children ?? []),
          recognizer: TapGestureRecognizer()
            ..onTap = () => onLinkTap?.call(href),
        );
      case 'img':
      case 'image':
        return WidgetSpan(
          child: _imagePlaceholder(node.attributes['alt'] ?? 'image'),
        );
      case 'br':
        return const TextSpan(text: '\n');
      case 'em':
      default:
        // Unknown/HTML inline: inert text.
        final text = _unescape(node.textContent);
        return text.isEmpty ? null : TextSpan(text: text);
    }
  }
}
