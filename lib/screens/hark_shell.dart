import 'package:flutter/material.dart';

import '../widgets/ambient_backdrop.dart';
import '../widgets/glass.dart';
import 'chat_screen.dart';
import 'cloud_computer_screen.dart';
import 'tasks_screen.dart';
import 'hark_home.dart';
import 'inbox_screen.dart';
import 'integrations_screen.dart';
import 'panels_screen.dart';
import 'projects_screen.dart';
import 'providers_screen.dart';
import 'vault_screen.dart';

enum HarkTab { home, chat, projects }

/// The Hark-style shell: ambient backdrop + floating glass UI.
/// Top nav pill (Home / Chat / Projects), dynamic body, pinned bottom input.
class HarkShell extends StatefulWidget {
  const HarkShell({super.key});

  @override
  State<HarkShell> createState() => _HarkShellState();
}

class _HarkShellState extends State<HarkShell> {
  HarkTab _tab = HarkTab.home;
  HarkTab _lastCoreTab = HarkTab.home;
  final GlobalKey<ChatScreenState> _chatKey = GlobalKey<ChatScreenState>();

  void _selectTab(HarkTab tab) {
    setState(() {
      if (tab != HarkTab.projects) _lastCoreTab = tab;
      _tab = tab;
    });
  }

  void _openPreferences() {
    if (_tab != HarkTab.projects) _lastCoreTab = _tab;
    setState(() => _tab = HarkTab.projects);
  }

  void _leavePreferences() => setState(() => _tab = _lastCoreTab);

  /// The glass input bar works on every screen: submitting from Home jumps to
  /// the Chat tab and delivers the message to the assistant.
  void _sendFromInput(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (_tab != HarkTab.chat) {
      _selectTab(HarkTab.chat);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _chatKey.currentState?.send(trimmed);
      });
    } else {
      _chatKey.currentState?.send(trimmed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool onPreferences = _tab == HarkTab.projects;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AmbientBackdrop(),
          SafeArea(
            child: Column(
              children: [
                _TopBar(
                  selected: _tab,
                  onSelect: _selectTab,
                  onMenu: _openPreferences,
                  onBack: _leavePreferences,
                ),
                Expanded(
                  child: onPreferences
                      ? const PreferencesScreen()
                      : _tab == HarkTab.home
                      ? const HarkHome()
                      : ChatScreen(key: _chatKey),
                ),
                if (!onPreferences) BottomInputBar(onSend: _sendFromInput),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.selected,
    required this.onSelect,
    required this.onMenu,
    required this.onBack,
  });

  final HarkTab selected;
  final ValueChanged<HarkTab> onSelect;
  final VoidCallback onMenu;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final bool onPreferences = selected == HarkTab.projects;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GlassIconButton(
            icon: onPreferences ? Icons.arrow_back_ios_new : Icons.menu,
            onTap: onPreferences ? onBack : onMenu,
          ),
          GlassContainer(
            key: const ValueKey('nav-pill'),
            radius: 30,
            opacity: 0.35,
            padding: const EdgeInsets.all(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _tabChip('Home', HarkTab.home),
                _tabChip('Chat', HarkTab.chat),
                _tabChip('Projects', HarkTab.projects),
              ],
            ),
          ),
          const _Avatar(),
        ],
      ),
    );
  }

  Widget _tabChip(String label, HarkTab tab) {
    final bool isSelected = selected == tab;
    return GestureDetector(
      key: ValueKey('tab-${label.toLowerCase()}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect(tab),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? Colors.white : Colors.black54,
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar();

  static const String _faceUrl =
      'https://images.unsplash.com/photo-1500648767791-00dcc994a43e'
      '?auto=format&fit=crop&w=200&q=80';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: ClipOval(
        child: Image.network(
          _faceUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.black87,
            alignment: Alignment.center,
            child: const Text(
              'S',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The pinned glass input bar. Hidden on the preferences screen.
class BottomInputBar extends StatelessWidget {
  const BottomInputBar({super.key, required this.onSend});

  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GlassContainer(
        key: const ValueKey('input-bar'),
        radius: 30,
        opacity: 0.35,
        padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                textInputAction: TextInputAction.send,
                onSubmitted: onSend,
                style: const TextStyle(fontSize: 16, color: Colors.black87),
                decoration: const InputDecoration(
                  hintText: 'Message Hark',
                  hintStyle: TextStyle(fontSize: 16, color: Colors.black54),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const _InputIcon(icon: Icons.add),
            const SizedBox(width: 12),
            const _InputIcon(icon: Icons.mic_none),
          ],
        ),
      ),
    );
  }
}

class _InputIcon extends StatelessWidget {
  const _InputIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // attachments + voice land in a later movement
      child: Icon(icon, size: 22, color: Colors.black87),
    );
  }
}

/// The Projects tab: System Preferences. One big glass card of rows.
class PreferencesScreen extends StatelessWidget {
  const PreferencesScreen({super.key});

  static const String version = 'v1.1.0';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'System Preferences',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Gork $version · glass shell',
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          GlassContainer(
            radius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                _row(Icons.palette_outlined, 'Theme', trailing: 'System'),
                const _Divider(),
                _row(Icons.storage_outlined, 'Data Management', trailing: 'On'),
                const _Divider(),
                _row(
                  Icons.shield_outlined,
                  'Security',
                  trailing: 'On',
                  onTap: () => _push(context, const VaultScreen()),
                ),
                const _Divider(),
                _row(Icons.info_outline, 'About', trailing: version),
                const _Divider(),
                _row(
                  Icons.key_outlined,
                  'Providers',
                  onTap: () => _push(context, const ProvidersScreen()),
                ),
                const _Divider(),
                _row(
                  Icons.folder_outlined,
                  'Projects',
                  onTap: () => _push(context, const ProjectsScreen()),
                ),
                const _Divider(),
                _row(
                  Icons.lock_outline,
                  'Vault',
                  onTap: () => _push(context, const VaultScreen()),
                ),
                const _Divider(),
                _row(
                  Icons.schedule_outlined,
                  'Tasks',
                  onTap: () => _push(context, const TasksScreen()),
                ),
                const _Divider(),
                _row(
                  Icons.inbox_outlined,
                  'Inbox',
                  onTap: () => _push(context, const InboxScreen()),
                ),
                const _Divider(),
                _row(
                  Icons.dashboard_outlined,
                  'Panels',
                  onTap: () => _push(context, const PanelsScreen()),
                ),
                const _Divider(),
                _row(
                  Icons.dns_outlined,
                  'Cloud Computer',
                  onTap: () => _push(context, const CloudComputerScreen()),
                ),
                const _Divider(),
                _row(
                  Icons.extension_outlined,
                  'Integrations',
                  onTap: () => _push(context, const IntegrationsScreen()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Widget _row(
    IconData icon,
    String label, {
    String? trailing,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.black87),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
            const Spacer(),
            if (trailing != null)
              Text(
                trailing,
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 20, color: Colors.black54),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(color: Colors.black12, height: 1);
  }
}
