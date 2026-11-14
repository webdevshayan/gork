import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../services/google_accounts.dart';
import '../services/integrations.dart';
import '../services/locator.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/g_button.dart';
import '../widgets/glass.dart';

/// Account selection: every connected Google account, the active one
/// marked. One tap on an account = one click that binds ALL Google
/// services to it. New accounts are added by pasting an OAuth token once
/// — the app verifies it and remembers it.
class GoogleAccountsScreen extends StatefulWidget {
  const GoogleAccountsScreen({super.key, this.store, this.report});

  /// Injectable for tests; defaults to the keystore-backed store.
  final GoogleAccountStore? store;
  final void Function(String summary)? report;

  @override
  State<GoogleAccountsScreen> createState() => _GoogleAccountsScreenState();
}

class _GoogleAccountsScreenState extends State<GoogleAccountsScreen> {
  late Future<List<GoogleAccount>> _accounts;
  String? _activeEmail;
  bool _connecting = false;

  GoogleAccountStore get _store =>
      widget.store ??
      GoogleAccountStore(
        store: Locator.store,
        verifier: GoogleAccountStore.gmailVerifier,
        vault: IntegrationVault(Locator.store),
      );

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _accounts = _store.accounts().then((a) async {
      _activeEmail = (await _store.active())?.email;
      return a;
    });
  }

  /// THE one click: active account + every Google service bound.
  Future<void> _connect(GoogleAccount acct) async {
    setState(() => _connecting = true);
    try {
      final connected = await _store.connectAll(acct.email);
      setState(() => _activeEmail = acct.email);
      final summary =
          'Connected ${connected.join(', ')} via ${acct.email}';
      widget.report?.call(summary);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(summary)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Connect failed: $e')));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _addAccount() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GlassColors.fillStrong,
        title: Text('Add Google account',
            style: TextStyle(color: GlassColors.text)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: GlassColors.text),
          decoration: InputDecoration(
            hintText: 'paste the OAuth access token',
            hintStyle: TextStyle(color: GlassColors.textFaint),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final acct = await _store.addAccount(controller.text.trim());
      setState(_reload);
      await _connect(acct);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(content: Text('Could not add account: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AmbientBackdrop(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                Row(
                  children: [
                    GlassIconButton(
                      key: const ValueKey('google-back'),
                      icon: Icons.u_turn_left,
                      onTap: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Google',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: GlassColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'One account, every Google service. Tap an account to '
                  'connect it everywhere.',
                  style: TextStyle(fontSize: 14, color: GlassColors.textDim),
                ),
                const SizedBox(height: 24),
                FutureBuilder<List<GoogleAccount>>(
                  future: _accounts,
                  builder: (context, snap) {
                    final accounts = snap.data ?? const <GoogleAccount>[];
                    if (accounts.isEmpty) {
                      return GlassContainer(
                        radius: 28,
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No Google account connected yet. Add one below — '
                          'it connects every Google service at once.',
                          style: TextStyle(
                              fontSize: 14, color: GlassColors.textDim),
                        ),
                      );
                    }
                    return GlassContainer(
                      radius: 28,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          for (var i = 0; i < accounts.length; i++) ...[
                            if (i > 0) Divider(
                                color: GlassColors.divider, height: 1),
                            GlassMenuRow(
                              key: ValueKey(
                                  'account-${accounts[i].email}'),
                              icon: accounts[i].email == _activeEmail
                                  ? Icons.verified_user_outlined
                                  : Icons.account_circle_outlined,
                              label: accounts[i].email,
                              trailing: _connecting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : GlassRadio(
                                      selected: accounts[i].email ==
                                          _activeEmail),
                              onTap: () => _connect(accounts[i]),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                GButton(
                  key: const ValueKey('google-add'),
                  label: 'Add account',
                  onPressed: _addAccount,
                  variant: ButtonVariant.secondary,
                  expands: true,
                ),
                const SizedBox(height: 8),
                Text(
                  'One-time setup — it stays connected until you remove it. '
                  'Tokens are stored encrypted on this device only.',
                  style: TextStyle(fontSize: 12, color: GlassColors.textFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
