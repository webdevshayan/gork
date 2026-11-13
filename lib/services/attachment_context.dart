import 'dart:convert';
import 'dart:io';

import 'history_store.dart';
import 'llm_client.dart';

/// Turns an attachment into what the model actually sees. Text files speak:
/// their content rides into the conversation, capped at a few thousand
/// chars. Images load as vision payloads for multimodal providers; anything
/// unreadable, oversized or of unknown type stays an honest marker.
class AttachmentContext {
  /// Characters of file content included per attachment.
  static const int maxChars = 4000;

  /// Raw bytes allowed per image (base64 inflates this by a third on the
  /// wire — 3 MB keeps requests sane).
  static const int maxImageBytes = 3 * 1024 * 1024;

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

  /// Loads an image attachment as a vision payload. Returns null — never
  /// throws — for non-images, missing files, unknown extensions or anything
  /// over [maxImageBytes]; the caller keeps the plain marker in that case.
  static ChatImage? loadImage(ChatAttachment attachment) {
    if (attachment.kind != 'image') return null;
    final mediaType = _imageMediaType(attachment.name);
    if (mediaType == null) return null;
    try {
      final file = File(attachment.path);
      if (file.lengthSync() > maxImageBytes) return null;
      final bytes = file.readAsBytesSync();
      if (bytes.isEmpty) return null;
      return ChatImage(mediaType, base64Encode(bytes));
    } catch (_) {
      return null;
    }
  }

  /// Only well-known web image types; honest null over guessing.
  static String? _imageMediaType(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return null;
    }
  }
}
