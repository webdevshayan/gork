import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../services/inbox_service.dart';
import '../services/locator.dart';
import '../widgets/g_button.dart';
import '../widgets/g_card.dart';
import '../widgets/screen.dart';

/// Proactive Inbox: gork suggests one-tap actions from live local signals.
/// Sensitive actions always ask for confirmation first.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<InboxAction> _actions = [];
  String? _message;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final actions = await Locator.inbox.suggestions();
      if (mounted) setState(() => _actions = actions);
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not build suggestions: $e');
    }
  }

  Future<void> _run(InboxAction action) async {
    if (action.requiresConfirm) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: paletteOf(context).surface,
          title: Text('Confirm action',
              style: TypeScale.heading(color: paletteOf(context).textPrimary)),
          content: Text('${action.ctaLabel} — ${action.title}?\n\n${action.detail}',
              style: TypeScale.body(color: paletteOf(context).textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final result = await Locator.inbox.perform(action);
    setState(() => _message = result);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Screen(
      title: 'Inbox',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        children: [
          GCard(
            child: Text(
              'gork watches local signals and suggests one-tap actions. '
              'Sensitive actions always ask first.',
              style: TypeScale.caption(color: palette.textSecondary),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: Spacing.md),
            Text(_message!, style: TypeScale.bodySmall(color: palette.success)),
          ],
          const SizedBox(height: Spacing.md),
          if (_actions.isEmpty)
            GCard(
              child: Text(
                'Nothing suggested right now. Check back later — suggestions '
                'appear from live weather and memory signals.',
                style: TypeScale.body(color: palette.textSecondary),
              ),
            ),
          for (final action in _actions)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.md),
              child: GCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(action.title,
                        style: TypeScale.heading(color: palette.textPrimary)),
                    const SizedBox(height: Spacing.xs),
                    Text(action.detail,
                        style: TypeScale.bodySmall(color: palette.textSecondary)),
                    const SizedBox(height: Spacing.md),
                    GButton(
                      label: action.ctaLabel,
                      onPressed: () => _run(action),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
