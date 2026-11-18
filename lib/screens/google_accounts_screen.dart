import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../services/google_accounts.dart';
import '../services/integrations.dart';
import 'package:file_picker/file_picker.dart';

import '../services/credential_uploader.dart';
import '../services/locator.dart';
import 'cloud_computer_screen.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/g_button.dart';
import '../widgets/glass.dart';

/// Account selection: every connected Google account, the active one
/// marked. One tap on an account = one click that binds ALL Google
/// services to it. New accounts are added by pasting an OAuth token once
/// — the app verifies it and remembers it.
class GoogleAccountsScreen extends StatefulWidget {
  const GoogleAccountsScreen(
      {super.key, this.store, this.report, this.uploader});

  /// Injectable for tests; defaults to the keystore-backed store.
  final GoogleAccountStore? store;
  final void Function(String summary)? report;

  /// Injectable for tests; defaults to the keystore-backed uploader.
  final GoogleCredentialsUploader? uploader;

  @override
  State<GoogleAccountsScreen> createState() => _GoogleAccountsScreenState();
}

class _GoogleAccountsScreenState extends State<GoogleAccountsScreen> {
  late Future<List<GoogleAccount>> _accounts;
  String? _activeEmail;
  bool _connecting = false;
  bool? _credsOnVps;

  GoogleCredentialsUploader get _uploader =>
      widget.uploader ?? GoogleCredentialsUploader();

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
    if (_uploader.configured) {
      _uploader.hasCredentials().then((v) {
        if (mounted) setState(() => _credsOnVps = v);
      });
    } else {
      _credsOnVps = null;
    }
  }

  /// The Cloud Console credentials JSON travels to the VPS vault exactly
  /// once; nothing is ever read back (status boolean only).
  ///
  /// Movement 56: the picker used FileType.custom + ['json'], which filters
  /// by MIME. Files downloaded from a browser often carry
  /// application/octet-stream, so the system document picker hid them and
  /// "no file could be uploaded". Pick ANY file, then validate the
  /// extension here in Dart.
  /// Movement 59 (screenshot bug): with no VPS configured this used to
  /// open the picker, upload nothing, and surface the raw exception
  /// ("Upload failed: Bad state: …"). Now the VPS is checked FIRST and the
  /// user is offered a direct jump to the Security screen; remaining
  /// failures speak human, not Dart.
  Future<void> _uploadCredentials() async {
    if (!_uploader.configured) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: GlassColors.fill,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RadiusTokens.lg),
          ),
          title: Text('Set up your VPS first',
              style: TextStyle(color: GlassColors.text)),
          content: Text(
            'Credentials are sealed on your VPS, so gork needs the VPS '
            'address before it can store anything. One address and one '
            'secret in Cloud Computer unlock this upload — and chat, '
            'tasks and the vault too.',
            style: TextStyle(color: GlassColors.textDim),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('Not now',
                  style: TextStyle(color: GlassColors.textDim)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('Set up the VPS',
                  style: TextStyle(color: GlassColors.text)),
            ),
          ],
        ),
      );
      if (go == true && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CloudComputerScreen()),
        );
      }
      return;
    }
    try {
      final picked = await FilePicker.platform.pickFiles(withData: false);
      if (picked == null || picked.files.single.path == null) return;
      final file = picked.files.single;
      if (!file.name.toLowerCase().endsWith('.json')) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text(
              'That is not a .json file — pick the credentials file '
              'downloaded from Google Cloud Console.')));
        return;
      }
      await _uploader.upload(file.path!);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content:
            Text('Credentials sealed on the VPS — never read back, only a status.')));
      _reload();
    } catch (e) {
      if (!mounted) return;
      // Speak human: strip Dart's exception prefixes and translate the
      // known cases; anything else shows the message without "Bad state:".
      String message;
      final text = e.toString();
      if (text.contains('SocketException') || text.contains('ClientException')) {
        message = 'Could not reach the VPS — check the address in Cloud '
            'Computer and your connection.';
      } else if (text.contains('the VPS refused the upload')) {
        // Movement 61: an old daemon 404s the credentials endpoint — name
        // the one-command fix instead of a vague "make sure it is up to
        // date". The update preserves config, keys, tasks and the vault.
        message = 'The VPS daemon is older than this app or not running. '
            'On the VPS run: gork daemon update — your API keys, tasks and '
            'vault are kept — then try again.';
      } else {
        message = text
            .replaceFirst(RegExp(r'^Bad state:\s*'), '')
            .replaceFirst(RegExp(r'^Invalid argument(\([^)]*\))?:\s*'), '');
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
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
                    GlassBackButton(
                      key: const ValueKey('google-back'),
                      label: 'Back',
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
                // Movement 61 gap fix: this card used to sit DIRECTLY on the
                // Add account pill (screenshot 2026-11-18) — two surfaces
                // touching reads as one broken card. Every stacked pair on
                // this screen gets the 16px gap.
                const SizedBox(height: 16),
                // Movement 55: the Cloud Console card used to be the
                // FIRST Stack child — painted UNDER the AmbientBackdrop and
                // never seen (the invisible 'Google Cloud Console → Upload').
                // It lives in the list now, so Menu → Google → Google Cloud
                // Console → Upload is actually reachable.
                GlassContainer(
                  radius: 24,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Google Cloud Console',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: GlassColors.text)),
                    const SizedBox(height: 4),
                    Text(
                      'Upload the credentials.json from Cloud Console once — it '
                      'is sealed on the VPS and never read back.',
                      style: TextStyle(fontSize: 13, color: GlassColors.textDim),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      key: const ValueKey('gconsole-upload'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _uploadCredentials,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text('Upload credentials.json',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                      ),
                    ),
                    if (_credsOnVps != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _credsOnVps!
                            ? 'Credentials sealed on the VPS ✓'
                            : 'No credentials stored yet.',
                        key: const ValueKey('gconsole-status'),
                        style: TextStyle(
                            fontSize: 13,
                            color: _credsOnVps!
                                ? GlassColors.text
                                : GlassColors.textDim),
                      ),
                    ],
                  ],
                ),
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
