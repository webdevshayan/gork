import 'dart:convert';
import 'dart:io';

import 'history_store.dart';

/// Turns an attachment into the text block the model actually sees.
/// Text files speak: their content rides into the conversation, capped at
/// a few thousand chars. Binaries and images stay honest markers — image
/// vision rides with multimodal providers in a later movement.
class AttachmentContext {
  /// Characters of file content included per attachment.
  static const int maxChars = 4000;

  static String describe(ChatAttachment attachment) {
    if (attachment.kind == 'image') {
      return '[image attached: ${attachment.name}]';
    }
    try {
      final bytes = File(attachment.path).readAsBytesSync();
      final text = utf8.decode(bytes, allowMalformed: true);
      if (_looksBinary(text)) {
        return '[file attached: ${attachment.name}]';
      }
      if (text.trim().isEmpty) {
        return '[file attached: ${attachment.name} — empty]';
      }
      var content = text;
      if (content.length > maxChars) {
        content = '${content.substring(0, maxChars)}\n[…truncated]';
      }
      return '[file attached: ${attachment.name}]\n```\n$content\n```';
    } catch (_) {
      return '[file attached: ${attachment.name} — content unavailable]';
    }
  }

  /// More than ~2% control or undecodable bytes means not text.
  static bool _looksBinary(String s) {
    var bad = 0;
    for (final code in s.codeUnits) {
      if (code == 0xFFFD || code < 9 || (code > 13 && code < 32)) bad++;
    }
    return bad * 50 > s.length;
  }
}
