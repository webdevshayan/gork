import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import 'glass.dart';

/// The pinned glass input bar, pixel-matched: hint "Message Hark", + and mic
/// on the right; the mic becomes a black send circle when there is text.
/// Shared by the shell and the pushed chat screens.
class BottomInputBar extends StatelessWidget {
  const BottomInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onAttach,
    this.hint = 'Message Hark',
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSend;
  final VoidCallback onAttach;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final bool hasText = value.text.trim().isNotEmpty;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: GlassContainer(
            key: const ValueKey('input-bar'),
            radius: 30,
            strong: true,
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    textInputAction: TextInputAction.send,
                    onSubmitted: onSend,
                    // The message area auto-resizes with the text instead of
                    // clipping long messages.
                    minLines: 1,
                    maxLines: 6,
                    style: TextStyle(
                      fontSize: 17,
                      color: GlassColors.text,
                    ),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: TextStyle(
                        fontSize: 17,
                        color: GlassColors.textDim,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                GestureDetector(
                  key: const ValueKey('attach-button'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onAttach,
                  child: Padding(
                    // 14, not 10: this box must match the mic's 52dp box —
                    // the row is END-aligned (bottom-pinned for multi-line),
                    // and a shorter box made the + ride ~4dp below the mic
                    // on a single line.
                    padding: EdgeInsets.all(14),
                    child: Icon(Icons.add, size: 24, color: GlassColors.textDim),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: hasText
                      ? GestureDetector(
                          key: const ValueKey('send-button'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onSend(controller.text),
                          child: Container(
                            key: const ValueKey('send-circle'),
                            width: 44,
                            height: 44,
                            margin: const EdgeInsets.fromLTRB(0, 0, 4, 4),
                            decoration: BoxDecoration(
                              // dark theme: light circle, dark arrow.
                              color: GlassColors.text,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_upward,
                              size: 22,
                              color: Colors.black,
                            ),
                          ),
                        )
                      : Padding(
                          key: ValueKey('mic-icon'),
                          padding: EdgeInsets.all(14),
                          child: Icon(
                            Icons.mic_none,
                            size: 24,
                            color: GlassColors.textDim,
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
