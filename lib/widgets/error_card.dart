import 'package:flutter/material.dart';

/// A provider error on the chat surface: one human line, never a raw JSON
/// blob. The raw provider body — codes, metadata, kilobytes of repeated
/// previous_errors — hides behind a Details expander for when it is
/// actually needed.
class ErrorDetailsCard extends StatefulWidget {
  const ErrorDetailsCard({super.key, required this.summary, this.details});

  /// The human one-liner (provider message + remedy hint).
  final String summary;

  /// The raw provider body, shown only when expanded. Null/empty hides the
  /// expander entirely.
  final String? details;

  @override
  State<ErrorDetailsCard> createState() => _ErrorDetailsCardState();
}

class _ErrorDetailsCardState extends State<ErrorDetailsCard> {
  bool _open = false;

  static const Color _red = Color(0xFFB91C1C);

  @override
  Widget build(BuildContext context) {
    final details = widget.details;
    final hasDetails = details != null && details.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _red.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, size: 18, color: _red),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.summary,
                  style: const TextStyle(
                      fontSize: 13, height: 1.35, color: _red),
                ),
              ),
              if (hasDetails)
                GestureDetector(
                  key: const ValueKey('error-details-toggle'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _open = !_open),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(
                      children: [
                        Text(
                          'Details',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _red.withValues(alpha: 0.8),
                          ),
                        ),
                        AnimatedRotation(
                          turns: _open ? 0.5 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: Icon(
                            Icons.expand_more,
                            size: 18,
                            color: _red.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          // AnimatedSize over a conditional child, not AnimatedCrossFade:
          // the collapsed state builds NOTHING for the raw body, so screen
          // readers and tests never see it while hidden.
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          details ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            fontFamily: 'monospace',
                            color:
                                Colors.red.shade900.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
