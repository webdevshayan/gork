import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../constants/design_tokens.dart';
import 'glass.dart';

/// The pinned glass input bar, pixel-matched: hint "Message Gork", + and mic
/// on the right; the mic becomes a black send circle when there is text.
/// Shared by the shell and the pushed chat screens.
///
/// Movement 56: the mic now actually listens — speech_to_text dictation
/// fills the draft with the recognized words (device locale, partial
/// results so the field types along). When the field already has text the
/// mic is replaced by the send circle, as before.
class BottomInputBar extends StatefulWidget {
  const BottomInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onAttach,
    this.hint = 'Message Gork',
    this.attachLink,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSend;
  final VoidCallback onAttach;
  final String hint;

  /// When provided, the + button is a CompositedTransformTarget — the shell
  /// pins its attach dropdown to the top edge of this trigger (Movement 57).
  final LayerLink? attachLink;

  @override
  State<BottomInputBar> createState() => _BottomInputBarState();
}

class _BottomInputBarState extends State<BottomInputBar> {
  final SpeechToText _speech = SpeechToText();
  bool _listening = false;

  @override
  void dispose() {
    if (_listening) _speech.stop();
    super.dispose();
  }

  /// Toggle dictation. The first tap initializes the engine (this is also
  /// where Android surfaces the RECORD_AUDIO runtime dialog); results are
  /// written into the draft as they arrive.
  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    try {
      final available = await _speech.initialize();
      if (!available) throw Exception('speech engine unavailable');
      if (!mounted) return;
      setState(() => _listening = true);
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          widget.controller.value = TextEditingValue(
            text: result.recognizedWords,
            selection: TextSelection.collapsed(
              offset: result.recognizedWords.length,
            ),
          );
          if (result.finalResult && mounted) {
            setState(() => _listening = false);
          }
        },
        listenOptions: SpeechListenOptions(
          cancelOnError: true,
          partialResults: true,
        ),
      );
    } catch (e) {
      debugPrint('voice input failed: $e');
      if (mounted) setState(() => _listening = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Voice input is unavailable — check the microphone permission.',
              ),
            ),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final bool hasText = value.text.trim().isNotEmpty;
        final String hint = _listening ? 'Listening…' : widget.hint;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: CompositedTransformTarget(
            // Movement 59: the attach dropdown anchors to the ROW's top
            // right, not the + icon. The row's right edge sits INSIDE the
            // screen by construction, so the menu can never clip off the
            // right edge (the screenshot bug: chevrons cut in half).
            link: widget.attachLink ?? LayerLink(),
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
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      textInputAction: TextInputAction.send,
                      onSubmitted: widget.onSend,
                      // The message area auto-resizes with the text instead of
                      // clipping long messages.
                      minLines: 1,
                      maxLines: 6,
                      style: TextStyle(fontSize: 17, color: GlassColors.text),
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
                    onTap: widget.onAttach,
                    child: Padding(
                      // 14, not 10: this box must match the mic's 52dp box —
                      // the row is END-aligned (bottom-pinned for
                      // multi-line), and a shorter box made the + ride ~4dp
                      // below the mic on a single line.
                      padding: EdgeInsets.all(14),
                      child: Icon(
                        Icons.add,
                        size: 24,
                        color: GlassColors.textDim,
                      ),
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
                            onTap: () => widget.onSend(widget.controller.text),
                            child: Container(
                              key: const ValueKey('send-circle'),
                              width: 44,
                              height: 44,
                              margin: const EdgeInsets.fromLTRB(0, 0, 4, 4),
                              decoration: BoxDecoration(
                                // Ink circle with the opposite-tone arrow:
                                // white arrow on black (light), black on
                                // near-white (dark).
                                color: GlassColors.text,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.arrow_upward,
                                size: 22,
                                color:
                                    GlassColors.brightness.value ==
                                        Brightness.dark
                                    ? Colors.black
                                    : Colors.white,
                              ),
                            ),
                          )
                        : GestureDetector(
                            key: const ValueKey('mic-button'),
                            behavior: HitTestBehavior.opaque,
                            onTap: _toggleMic,
                            child: Padding(
                              key: ValueKey('mic-icon'),
                              padding: EdgeInsets.all(14),
                              child: Icon(
                                _listening ? Icons.mic : Icons.mic_none,
                                size: 24,
                                color: _listening
                                    ? GlassColors.text
                                    : GlassColors.textDim,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
