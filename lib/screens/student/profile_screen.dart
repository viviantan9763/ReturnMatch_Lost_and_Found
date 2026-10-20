import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../widgets/student/student_shell.dart';

import '../login_screen.dart';
import 'my_claims_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  // =========================================================
  // LOGOUT
  // =========================================================

  Future<void> _logout(
    BuildContext context,
  ) async {
    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          title: const Text(
            'Sign Out',
          ),
          content: const Text(
            'Are you sure you want to sign out?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text(
                'Cancel',
              ),
            ),

            ElevatedButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    AppColors.studentPrimary,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Sign Out',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    AuthService.logout();

    if (!context.mounted) {
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const LoginScreen(),
      ),
      (route) => false,
    );
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return StudentShell(
      selectedPage: StudentPage.profile,
      title: 'Profile',
      child: Container(
        color: AppColors.background,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 850,
              ),
              child: Column(
                children: [
                  // ==========================================
                  // PROFILE HEADER
                  // ==========================================

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.border,
                      ),
                    ),
                    child: const Column(
                      children: [
                        CircleAvatar(
                          radius: 45,
                          backgroundColor:
                              AppColors.studentSoft,
                          child: Icon(
                            Icons.person,
                            size: 50,
                            color:
                                AppColors.studentPrimary,
                          ),
                        ),

                        SizedBox(height: 14),

                        Text(
                          'Student / Staff',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight:
                                FontWeight.w800,
                            color:
                                AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ==========================================
                  // PROFILE INFORMATION
                  // ==========================================

                  _sectionTitle(
                    'Personal Information',
                  ),

                  const SizedBox(height: 10),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 28,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.border,
                      ),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 36,
                          color:
                              AppColors.studentPrimary,
                        ),

                        SizedBox(height: 12),

                        Text(
                          'Profile Information',
                          style: TextStyle(
                            color:
                                AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight:
                                FontWeight.w800,
                          ),
                        ),

                        SizedBox(height: 6),

                        Text(
                          'User profile information will appear here when the profile module is connected.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors
                                .textSecondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ==========================================
                  // ACTIVITY
                  // ==========================================

                  _sectionTitle(
                    'My Activity',
                  ),

                  const SizedBox(height: 10),

                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.border,
                      ),
                    ),
                    child: Column(
                      children: [
                        _MenuTile(
                          icon:
                              Icons.search_off_outlined,
                          title: 'My Lost Reports',
                          subtitle:
                              'View your submitted lost-item reports',
                          onTap: () {
                            // My Reports API/page
                            // will be connected later.
                          },
                        ),

                        const Divider(
                          height: 1,
                          color: AppColors.border,
                        ),

                        _MenuTile(
                          icon: Icons
                              .inventory_2_outlined,
                          title: 'My Found Reports',
                          subtitle:
                              'View your submitted found-item reports',
                          onTap: () {
                            // My Reports API/page
                            // will be connected later.
                          },
                        ),

                        const Divider(
                          height: 1,
                          color: AppColors.border,
                        ),

                        _MenuTile(
                          icon: Icons
                              .verified_user_outlined,
                          title: 'My Claims',
                          subtitle:
                              'Track your submitted claim requests',
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const MyClaimsScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ==========================================
                  // SIGN OUT
                  // ==========================================

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _logout(
                          context,
                        );
                      },
                      style:
                          OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(
                          color: Colors.red,
                        ),
                      ),
                      icon: const Icon(
                        Icons.logout_rounded,
                      ),
                      label: const Text(
                        'Sign Out',
                      ),
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

  // =========================================================
  // SECTION TITLE
  // =========================================================

  Widget _sectionTitle(
    String title,
  ) {
    return Align(
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
  }
}

// ===========================================================
// MENU TILE
// ===========================================================

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 4,
      ),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.studentSoft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: AppColors.studentPrimary,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textSecondary,
      ),
      onTap: onTap,
    );
  }
}