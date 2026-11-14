import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../services/profile_info.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/g_button.dart';
import '../widgets/glass.dart';

/// The Profile form: name and email, editable, persisted on this device
/// only. The reference header values stay as defaults until the user
/// saves their own.
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _name =
      TextEditingController(text: profileName.value);
  late final TextEditingController _email =
      TextEditingController(text: profileEmail.value);

  static final RegExp _emailRe =
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<void> _save() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Enter a name')));
      return;
    }
    if (!_emailRe.hasMatch(email)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('Enter a valid email')));
      return;
    }
    await saveProfile(name: name, email: email);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Profile saved')));
    Navigator.pop(context);
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
                      key: const ValueKey('profile-back'),
                      icon: Icons.u_turn_left,
                      onTap: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Profile',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: GlassColors.text,
                  ),
                ),
                const SizedBox(height: 24),
                GlassContainer(
                  radius: 28,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Name',
                          style: TextStyle(
                              fontSize: 14, color: GlassColors.textDim)),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('profile-name-field'),
                        controller: _name,
                        style: TextStyle(color: GlassColors.text),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'your name',
                          hintStyle:
                              TextStyle(color: GlassColors.textFaint),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GlassContainer(
                  radius: 28,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Email',
                          style: TextStyle(
                              fontSize: 14, color: GlassColors.textDim)),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('profile-email-field'),
                        controller: _email,
                        style: TextStyle(color: GlassColors.text),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'you@example.com',
                          hintStyle:
                              TextStyle(color: GlassColors.textFaint),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                GButton(
                  key: const ValueKey('profile-save'),
                  label: 'Save',
                  onPressed: _save,
                  expands: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
