import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import 'glass.dart';
import '../widgets/glass.dart';

/// What the + (attachment) menu offers.
enum AttachKind { camera, photos, files }

/// The + dropdown — Camera / Photos / Files on opaque glass. Shared by the
/// shell (inline under the +) and pushed chat pages (as a floating sheet).
/// Every + entry point MUST show this menu first; a picker is only opened
/// after a row is chosen — never directly.
class AttachMenu extends StatelessWidget {
  const AttachMenu({super.key, required this.onPick});

  final ValueChanged<AttachKind> onPick;

  /// Presents the menu as a small floating sheet above the input bar and
  /// resolves with the chosen kind (null = dismissed).
  static Future<AttachKind?> show(BuildContext context) {
    return showGorkSheet<AttachKind>(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: AttachMenu(
            onPick: (kind) => Navigator.of(context).pop(kind),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      key: const ValueKey('attach-menu'),
      radius: 24,
      opacity: 0.6,
      width: 220,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(context, Icons.photo_camera_outlined, 'Camera', AttachKind.camera),
          Divider(color: GlassColors.divider, height: 1),
          _row(context, Icons.image_outlined, 'Photos', AttachKind.photos),
          Divider(color: GlassColors.divider, height: 1),
          _row(context, Icons.folder_outlined, 'Files', AttachKind.files),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String label,
    AttachKind kind,
  ) {
    return GlassMenuRow(
      icon: icon,
      label: label,
      onTap: () => onPick(kind),
    );
  }
}
