import 'package:flutter/material.dart';

import '../services/history_store.dart';
import '../services/locator.dart';
import '../services/projects_store.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/glass.dart';
import 'cloud_computer_screen.dart';
import 'inbox_screen.dart';
import 'integrations_screen.dart';
import 'panels_screen.dart';
import 'projects_screen.dart';
import 'providers_screen.dart';
import 'tasks_screen.dart';
import 'theme_page.dart';
import 'wallet_screen.dart';
import '../constants/design_tokens.dart';

/// What the search covers — the entry point preselects the scope (home =
/// everything, a chat = that conversation, projects = projects only) and the
/// chips let the user widen or narrow it.
enum SearchScope { all, chat, projects }

/// Chat search from the reference: a glass query field over the ambient sky,
/// hits across conversations (title + matched snippet + date), quick feature
/// jumps and recent chats while the query is empty. Opening a chat hit hands
/// the conversation id to the shell; project hits open the workspace screen.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.onOpenChat,
    this.initialScope = SearchScope.all,
    this.conversationId,
  });

  final ValueChanged<String> onOpenChat;

  /// The scope the overlay was opened with.
  final SearchScope initialScope;

  /// The active conversation when opened from the Chat tab.
  final String? conversationId;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _field = TextEditingController();
  String _query = '';
  late SearchScope _scope = widget.initialScope;

  static const List<_Jump> _jumps = [
    _Jump('Inbox', Icons.inbox_outlined, InboxScreen()),
    _Jump('Panels', Icons.dashboard_outlined, PanelsScreen()),
    _Jump('Projects', Icons.folder_outlined, ProjectsScreen()),
    _Jump('Wallet', Icons.account_balance_wallet_outlined, WalletScreen()),
    _Jump('Cloud Computer', Icons.dns_outlined, CloudComputerScreen()),
    _Jump('Integrations', Icons.extension_outlined, IntegrationsScreen()),
    _Jump('Scheduled Tasks', Icons.schedule_outlined, TasksScreen()),
    _Jump('Providers', Icons.key_outlined, ProvidersScreen()),
    _Jump('Theme', Icons.palette_outlined, ThemePage()),
  ];

  List<_Hit> _chatHits(String query) {
    final lower = query.toLowerCase();
    Iterable<Conversation> conversations = Locator.history.all();
    if (_scope == SearchScope.chat && widget.conversationId != null) {
      final one =
          conversations.where((c) => c.id == widget.conversationId).toList();
      if (one.isNotEmpty) conversations = one;
    }
    final out = <_Hit>[];
    for (final conv in conversations) {
      for (final m in conv.messages) {
        final index = m.content.toLowerCase().indexOf(lower);
        if (index < 0) continue;
        final start = index > 40 ? index - 40 : 0;
        final end = index + query.length + 60 < m.content.length
            ? index + query.length + 60
            : m.content.length;
        var snippet =
            m.content.substring(start, end).replaceAll('\n', ' ').trim();
        if (start > 0) snippet = '…$snippet';
        if (end < m.content.length) snippet = '$snippet…';
        out.add(_Hit(conv, snippet));
        break; // one card per conversation — the thread itself follows.
      }
    }
    return out;
  }

  List<Project> _projectHits(String query) {
    final lower = query.toLowerCase();
    return [
      for (final p in Locator.projects.all())
        if (p.title.toLowerCase().contains(lower) ||
            p.notes.toLowerCase().contains(lower))
          p,
    ];
  }

  String _dateLabel(int ms) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December',
    ];
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${months[d.month - 1]} ${d.day}';
  }

  String _scopeLabel(SearchScope scope) => switch (scope) {
        SearchScope.all => 'All',
        SearchScope.chat => 'This chat',
        SearchScope.projects => 'Projects',
      };

  @override
  Widget build(BuildContext context) {
    final bool empty = _query.trim().isEmpty;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AmbientBackdrop(),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      GlassIconButton(
                        icon: Icons.arrow_back_ios_new,
                        semanticLabel: 'Close search',
                        onTap: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: _SearchTitle(),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GlassContainer(
                    key: const ValueKey('search-field'),
                    radius: 30,
                    opacity: 0.45,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: TextField(
                      autofocus: true,
                      controller: _field,
                      onChanged: (q) => setState(() => _query = q),
                      style: TextStyle(
                          fontSize: 17, color: GlassColors.text),
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.search,
                            size: 20, color: GlassColors.textDim),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: Icon(Icons.close,
                                    size: 18, color: GlassColors.textDim),
                                onPressed: () {
                                  _field.clear();
                                  setState(() => _query = '');
                                },
                              ),
                        hintText: _scope == SearchScope.chat
                            ? 'Search this chat'
                            : _scope == SearchScope.projects
                                ? 'Search your projects'
                                : 'Search your chats',
                        hintStyle: TextStyle(
                            fontSize: 16, color: GlassColors.textDim),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Scope chips: the overlay opens pre-scoped, the user can
                // widen or narrow it from here.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (final scope in SearchScope.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            key: ValueKey('search-scope-${scope.name}'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() => _scope = scope),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: _scope == scope
                                    ? GlassColors.chip
                                    : GlassColors.fill,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: GlassColors.border),
                              ),
                              child: Text(
                                _scopeLabel(scope),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _scope == scope
                                      ? GlassColors.textOnChip
                                      : GlassColors.textDim,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: empty ? _emptyState() : _resultList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _emptyState() {
    if (_scope == SearchScope.projects) {
      return [
        Text(
          'Search your workspaces by name — folders, files, images and their '
          'chats live inside each one.',
          style: TextStyle(fontSize: 14, color: GlassColors.textDim),
        ),
      ];
    }
    final recents = Locator.history.all().take(5).toList();
    return [
      Text(
        'Jump to',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: GlassColors.textDim,
        ),
      ),
      const SizedBox(height: 8),
      GlassContainer(
        radius: 28,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (final jump in _jumps)
              GlassMenuRow(
                icon: jump.icon,
                label: jump.label,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => jump.screen),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'Recent',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: GlassColors.textDim,
        ),
      ),
      const SizedBox(height: 8),
      if (recents.isEmpty)
        Text(
          'No chats yet — say something to gork and it will show up here.',
          style: TextStyle(fontSize: 14, color: GlassColors.textDim),
        ),
      for (final conv in recents)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _HitCard(
            title: conv.title,
            date: _dateLabel(conv.updatedAt),
            snippet: '${conv.messages.length} messages',
            onTap: () => widget.onOpenChat(conv.id),
          ),
        ),
    ];
  }

  List<Widget> _resultList() {
    final query = _query.trim();
    final bool showChats = _scope != SearchScope.projects;
    final bool showProjects = _scope != SearchScope.chat;
    final chatHits = showChats ? _chatHits(query) : <_Hit>[];
    final projectHits = showProjects ? _projectHits(query) : <Project>[];

    if (chatHits.isEmpty && projectHits.isEmpty) {
      return [
        GlassContainer(
          radius: 24,
          padding: const EdgeInsets.all(20),
          child: Text(
            'No results for "$query".',
            style: TextStyle(fontSize: 16, color: GlassColors.textDim),
          ),
        ),
      ];
    }

    return [
      for (final hit in chatHits)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _HitCard(
            title: hit.conversation.title,
            date: _dateLabel(hit.conversation.updatedAt),
            snippet: hit.snippet,
            onTap: () => widget.onOpenChat(hit.conversation.id),
          ),
        ),
      if (chatHits.isNotEmpty && projectHits.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          'Projects',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: GlassColors.textDim,
          ),
        ),
        const SizedBox(height: 8),
      ],
      for (final project in projectHits)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _HitCard(
            title: project.title,
            date: _dateLabel(project.updatedAt),
            snippet: '${project.chats.length} chats · '
                '${project.files.length} files · '
                '${project.images.length} images',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProjectDetailScreen(
                  projectId: project.id,
                  onOpenChat: widget.onOpenChat,
                ),
              ),
            ),
          ),
        ),
    ];
  }
}

/// The big title — kept as a widget so the build stays readable.
class _SearchTitle extends StatelessWidget {
  const _SearchTitle();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Search',
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: GlassColors.text,
      ),
    );
  }
}

/// One search card: conversation title, date, and the matched context.
class _HitCard extends StatelessWidget {
  const _HitCard({
    required this.title,
    required this.date,
    required this.snippet,
    required this.onTap,
  });

  final String title;
  final String date;
  final String snippet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: GlassColors.fill,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: GlassColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: GlassColors.text,
                    ),
                  ),
                ),
                Text(
                  date,
                  style: TextStyle(
                      fontSize: 12, color: GlassColors.textDim),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              snippet,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: GlassColors.textDim),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Icon(Icons.chevron_right, size: 18, color: GlassColors.textDim),
            ),
          ],
        ),
      ),
    );
  }
}

class _Jump {
  const _Jump(this.label, this.icon, this.screen);
  final String label;
  final IconData icon;
  final Widget screen;
}

class _Hit {
  const _Hit(this.conversation, this.snippet);
  final Conversation conversation;
  final String snippet;
}
