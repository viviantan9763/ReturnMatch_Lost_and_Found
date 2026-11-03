import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../widgets/student/student_shell.dart';
import '../login_screen.dart';
import 'my_claims_screen.dart';
import 'my_reports_screen.dart';

/// Profile data is loaded from the authenticated /api/profile endpoint.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _user;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  String _message(http.Response response, String fallback) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message'].toString();
      }
    } catch (_) {}
    return '$fallback (HTTP ${response.statusCode})';
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/profile'),
        headers: AuthService.authenticatedHeaders(),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception(_message(response, 'Unable to load profile'));
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['user'] is! Map) {
        throw const FormatException('Invalid profile response');
      }
      final user = Map<String, dynamic>.from(decoded['user'] as Map);
      AuthService.currentUser = user;
      if (!mounted) return;
      setState(() {
        _user = user;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _editProfile() async {
    final user = _user;
    if (user == null) return;
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: '${user['name'] ?? ''}');
    final phoneController = TextEditingController(text: '${user['phone_no'] ?? ''}');
    bool saving = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, updateDialog) => AlertDialog(
            title: const Text('Edit Profile'),
            content: SizedBox(
              width: 430,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      enabled: !saving,
                      maxLength: 100,
                      decoration: const InputDecoration(labelText: 'Full Name'),
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? 'Name is required'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: phoneController,
                      enabled: !saving,
                      maxLength: 30,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number (Optional)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Email and account role cannot be changed here.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false)) return;
                        updateDialog(() => saving = true);
                        try {
                          final response = await http.patch(
                            Uri.parse('${AuthService.baseUrl}/profile'),
                            headers: AuthService.authenticatedHeaders(),
                            body: jsonEncode({
                              'name': nameController.text.trim(),
                              'phone_no': phoneController.text.trim().isEmpty
                                  ? null
                                  : phoneController.text.trim(),
                            }),
                          ).timeout(const Duration(seconds: 20));
                          if (response.statusCode != 200) {
                            throw Exception(_message(response, 'Could not update profile'));
                          }
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          await _loadProfile();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Profile updated successfully')),
                            );
                          }
                        } catch (error) {
                          if (dialogContext.mounted) {
                            updateDialog(() => saving = false);
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
                            );
                          }
                        }
                      },
                style: FilledButton.styleFrom(backgroundColor: AppColors.studentPrimary),
                child: Text(saving ? 'Saving...' : 'Save Changes'),
              ),
            ],
          ),
        ),
      );
    } finally {
      // Allow the dialog's closing transition to detach its text fields.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      nameController.dispose();
      phoneController.dispose();
    }
  }

  Future<void> _changePassword() async {
    final formKey = GlobalKey<FormState>();
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    bool submitting = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, updateDialog) => AlertDialog(
            title: const Text('Change Password'),
            content: SizedBox(
              width: 430,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: current,
                      obscureText: true,
                      enabled: !submitting,
                      decoration: const InputDecoration(labelText: 'Current Password'),
                      validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: next,
                      obscureText: true,
                      enabled: !submitting,
                      decoration: const InputDecoration(labelText: 'New Password'),
                      validator: (v) {
                        if (v == null || v.length < 12) {
                          return 'Use at least 12 characters';
                        }
                        if (v == current.text) return 'Choose a different password';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirm,
                      obscureText: true,
                      enabled: !submitting,
                      decoration: const InputDecoration(labelText: 'Confirm New Password'),
                      validator: (v) => v != next.text ? 'Passwords do not match' : null,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Password changes require your current password.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: submitting
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false)) return;
                        updateDialog(() => submitting = true);
                        try {
                          final response = await http.patch(
                            Uri.parse('${AuthService.baseUrl}/profile/password'),
                            headers: AuthService.authenticatedHeaders(),
                            body: jsonEncode({
                              'current_password': current.text,
                              'new_password': next.text,
                            }),
                          ).timeout(const Duration(seconds: 20));
                          if (response.statusCode != 200) {
                            throw Exception(_message(response, 'Unable to change password'));
                          }
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Password changed successfully')),
                            );
                          }
                        } catch (error) {
                          if (dialogContext.mounted) {
                            updateDialog(() => submitting = false);
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
                            );
                          }
                        }
                      },
                style: FilledButton.styleFrom(backgroundColor: AppColors.studentPrimary),
                child: Text(submitting ? 'Updating...' : 'Update Password'),
              ),
            ],
          ),
        ),
      );
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      current.dispose();
      next.dispose();
      confirm.dispose();
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.studentPrimary),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    AuthService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _goTo(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Widget _sectionTitle(String title) => Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      );

  Widget _field(String label, Object? value, IconData icon) {
    final display = (value ?? '').toString().trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.studentPrimary, size: 20),
          const SizedBox(width: 12),
          SizedBox(
            width: 105,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(
              display.isEmpty ? 'Not provided' : display,
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileInfo() {
    if (_loading) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(35),
        child: CircularProgressIndicator(),
      ));
    }
    if (_error != null) {
      return Column(
        children: [
          Text('Unable to load profile: $_error'),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loadProfile,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      );
    }
    final user = _user!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field('Full Name', user['name'], Icons.person_outline),
        const Divider(height: 1),
        _field('Email', user['email'], Icons.email_outlined),
        const Divider(height: 1),
        _field('Phone', user['phone_no'], Icons.phone_outlined),
        const Divider(height: 1),
        _field('Role', user['role'], Icons.badge_outlined),
        const Divider(height: 1),
        _field('Account', user['account_status'], Icons.verified_user_outlined),
        const SizedBox(height: 15),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _editProfile,
              style: FilledButton.styleFrom(backgroundColor: AppColors.studentPrimary),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit Profile'),
            ),
            OutlinedButton.icon(
              onPressed: _changePassword,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Change Password'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StudentShell(
      selectedPage: StudentPage.profile,
      title: 'Profile',
      child: Container(
        color: AppColors.background,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        const CircleAvatar(
                          radius: 45,
                          backgroundColor: AppColors.studentSoft,
                          child: Icon(Icons.person, size: 50, color: AppColors.studentPrimary),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          (_user?['name'] ?? 'Student / Staff').toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('Personal Information'),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: _profileInfo(),
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('My Activity'),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        _ProfileMenuTile(
                          icon: Icons.search_off_outlined,
                          title: 'My Lost Reports',
                          subtitle: 'View your submitted lost-item reports',
                          onTap: () => _goTo(const MyReportsScreen(itemType: 'LOST')),
                        ),
                        const Divider(height: 1, color: AppColors.border),
                        _ProfileMenuTile(
                          icon: Icons.inventory_2_outlined,
                          title: 'My Found Reports',
                          subtitle: 'View your submitted found-item reports',
                          onTap: () => _goTo(const MyReportsScreen(itemType: 'FOUND')),
                        ),
                        const Divider(height: 1, color: AppColors.border),
                        _ProfileMenuTile(
                          icon: Icons.verified_user_outlined,
                          title: 'My Claims',
                          subtitle: 'Track your submitted claim requests',
                          onTap: () => _goTo(const MyClaimsScreen()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _logout,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Sign Out'),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ProfileMenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.studentSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.studentPrimary, size: 20),
        ),
        title: Text(title, style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        )),
        subtitle: Text(subtitle, style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
        )),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
        onTap: onTap,
      );
}
