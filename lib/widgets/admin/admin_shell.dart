import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';

import '../../screens/login_screen.dart';
import '../../screens/admin/admin_dashboard_screen.dart';
import '../../screens/admin/item_management_screen.dart';
import '../../screens/admin/claim_review_screen.dart';
import '../../screens/admin/otp_collection_screen.dart';
import '../../screens/admin/retention_screen.dart';
import '../../screens/admin/disposal_record_screen.dart';
import '../../screens/admin/audit_log_screen.dart';
import '../../screens/admin/system_settings_screen.dart';
import '../../screens/admin/create_admin_screen.dart';

enum AdminPage {
  dashboard,
  items,
  claims,
  otpCollection,
  retention,
  disposal,
  audit,
  settings,
  adminManagement,
}

class AdminShell extends StatefulWidget {
  final AdminPage selectedPage;
  final Widget child;

  const AdminShell({
    super.key,
    required this.selectedPage,
    required this.child,
  });

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  static const double _expandedWidth = 250;
  static const double _collapsedWidth = 76;
  static const double _desktopBreakpoint = 950;

  // Static so the sidebar keeps its state when switching
  // between top-level admin pages.
  static bool _desktopExpanded = true;

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        MediaQuery.of(context).size.width >= _desktopBreakpoint;

    return Scaffold(
      backgroundColor: AppColors.background,

      // ==========================================================
      // MOBILE DRAWER
      // ==========================================================

      drawer: isDesktop
          ? null
          : Drawer(
              width: 270,
              child: _sidebar(
                drawerMode: true,
                expanded: true,
              ),
            ),

      appBar: isDesktop
          ? null
          : AppBar(
              backgroundColor: AppColors.adminPrimary,
              foregroundColor: Colors.white,
              elevation: 0,
              titleSpacing: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ReturnMatch',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _pageTitle(widget.selectedPage),
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

      // ==========================================================
      // DESKTOP
      // ==========================================================

      body: isDesktop
          ? Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  width: _desktopExpanded
                      ? _expandedWidth
                      : _collapsedWidth,
                  child: _sidebar(
                    drawerMode: false,
                    expanded: _desktopExpanded,
                  ),
                ),
                Expanded(
                  child: widget.child,
                ),
              ],
            )
          : widget.child,
    );
  }

  // ============================================================
  // SIDEBAR
  // ============================================================

  Widget _sidebar({
    required bool drawerMode,
    required bool expanded,
  }) {
    return Container(
      height: double.infinity,
      color: AppColors.adminDark,
      child: SafeArea(
        child: Column(
          children: [
            // ====================================================
            // BRAND
            // ====================================================

            _brandHeader(
              drawerMode: drawerMode,
              expanded: expanded,
            ),

            Container(
              height: 1,
              margin: EdgeInsets.symmetric(
                horizontal: expanded ? 18 : 12,
              ),
              color: Colors.white.withValues(
                alpha: 0.10,
              ),
            ),

            const SizedBox(height: 14),

            // ====================================================
            // NAVIGATION
            // ====================================================

            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: expanded ? 12 : 9,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _navItem(
                      page: AdminPage.dashboard,
                      icon: Icons.dashboard_outlined,
                      activeIcon: Icons.dashboard_rounded,
                      title: 'Dashboard',
                      drawerMode: drawerMode,
                      expanded: expanded,
                    ),

                    _navItem(
                      page: AdminPage.items,
                      icon: Icons.inventory_2_outlined,
                      activeIcon: Icons.inventory_2_rounded,
                      title: 'Item Management',
                      drawerMode: drawerMode,
                      expanded: expanded,
                    ),

                    _navItem(
                      page: AdminPage.claims,
                      icon: Icons.verified_user_outlined,
                      activeIcon: Icons.verified_user_rounded,
                      title: 'Claim Review',
                      drawerMode: drawerMode,
                      expanded: expanded,
                    ),

                    _navItem(
                      page: AdminPage.otpCollection,
                      icon: Icons.pin_outlined,
                      activeIcon: Icons.pin_rounded,
                      title: 'OTP Collection',
                      drawerMode: drawerMode,
                      expanded: expanded,
                    ),

                    _navItem(
                      page: AdminPage.retention,
                      icon: Icons.schedule_outlined,
                      activeIcon: Icons.schedule_rounded,
                      title: 'Retention',
                      drawerMode: drawerMode,
                      expanded: expanded,
                    ),

                    _navItem(
                      page: AdminPage.disposal,
                      icon: Icons.delete_outline_rounded,
                      activeIcon: Icons.delete_rounded,
                      title: 'Disposal Records',
                      drawerMode: drawerMode,
                      expanded: expanded,
                    ),

                    _navItem(
                      page: AdminPage.audit,
                      icon: Icons.fact_check_outlined,
                      activeIcon: Icons.fact_check_rounded,
                      title: 'Audit Log',
                      drawerMode: drawerMode,
                      expanded: expanded,
                    ),

                    const SizedBox(height: 20),

                    if (expanded)
                      const Padding(
                        padding: EdgeInsets.only(
                          left: 13,
                          bottom: 8,
                        ),
                        child: Text(
                          'MANAGEMENT',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 7,
                        ),
                        child: Divider(
                          color: Colors.white.withValues(
                            alpha: 0.10,
                          ),
                          height: 1,
                        ),
                      ),

                    _navItem(
                      page: AdminPage.settings,
                      icon: Icons.settings_outlined,
                      activeIcon: Icons.settings_rounded,
                      title: 'System Settings',
                      drawerMode: drawerMode,
                      expanded: expanded,
                    ),

                    _navItem(
                      page: AdminPage.adminManagement,
                      icon: Icons.manage_accounts_outlined,
                      activeIcon: Icons.manage_accounts_rounded,
                      title: 'Admin Management',
                      drawerMode: drawerMode,
                      expanded: expanded,
                    ),
                  ],
                ),
              ),
            ),

            // ====================================================
            // FOOTER
            // ====================================================

            _footer(
              expanded: expanded,
              drawerMode: drawerMode,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BRAND HEADER
  // ============================================================

  Widget _brandHeader({
    required bool drawerMode,
    required bool expanded,
  }) {
    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 18,
        ),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                  alpha: 0.10,
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.find_in_page_outlined,
                color: Colors.white,
                size: 23,
              ),
            ),

            if (!drawerMode) ...[
              const SizedBox(height: 12),
              _collapseButton(
                expanded: false,
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        20,
        12,
        18,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: 0.10,
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.find_in_page_outlined,
              color: Colors.white,
              size: 23,
            ),
          ),

          const SizedBox(width: 12),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ReturnMatch',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'ADMIN PORTAL',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),

          if (!drawerMode)
            _collapseButton(
              expanded: true,
            ),
        ],
      ),
    );
  }

  // ============================================================
  // COLLAPSE BUTTON
  // ============================================================

  Widget _collapseButton({
    required bool expanded,
  }) {
    return Tooltip(
      message: expanded
          ? 'Collapse sidebar'
          : 'Expand sidebar',
      child: Material(
        color: Colors.white.withValues(
          alpha: 0.08,
        ),
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: () {
            setState(() {
              _desktopExpanded = !_desktopExpanded;
            });
          },
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              expanded
                  ? Icons.chevron_left_rounded
                  : Icons.chevron_right_rounded,
              color: Colors.white70,
              size: 21,
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // NAV ITEM
  // ============================================================

  Widget _navItem({
    required AdminPage page,
    required IconData icon,
    required IconData activeIcon,
    required String title,
    required bool drawerMode,
    required bool expanded,
  }) {
    final selected =
        widget.selectedPage == page;

    final tile = Material(
      color: selected
          ? Colors.white.withValues(
              alpha: 0.11,
            )
          : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () {
          if (drawerMode) {
            Navigator.pop(context);
          }

          if (selected) {
            return;
          }

          _navigateTo(page);
        },
        child: Container(
          height: 46,
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 13 : 0,
          ),
          decoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  border: Border(
                    left: BorderSide(
                      color: Colors.white,
                      width: expanded ? 3 : 2,
                    ),
                  ),
                )
              : null,
          child: Row(
            mainAxisAlignment: expanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Icon(
                selected ? activeIcon : icon,
                color: selected
                    ? Colors.white
                    : Colors.white60,
                size: 20,
              ),

              if (expanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : Colors.white70,
                      fontSize: 12.5,
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(
        bottom: 4,
      ),
      child: expanded
          ? tile
          : Tooltip(
              message: title,
              waitDuration:
                  const Duration(milliseconds: 300),
              child: tile,
            ),
    );
  }

  // ============================================================
  // FOOTER
  // ============================================================

  Widget _footer({
    required bool expanded,
    required bool drawerMode,
  }) {
    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          9,
          8,
          9,
          12,
        ),
        child: Tooltip(
          message: 'Sign Out',
          child: Material(
            color: Colors.white.withValues(
              alpha: 0.06,
            ),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: _signOut,
              borderRadius: BorderRadius.circular(8),
              child: const SizedBox(
                width: double.infinity,
                height: 48,
                child: Icon(
                  Icons.logout_rounded,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(
          alpha: 0.06,
        ),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: Colors.white.withValues(
            alpha: 0.08,
          ),
        ),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              13,
              13,
              13,
              9,
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white12,
                  child: Icon(
                    Icons.person_outline_rounded,
                    color: Colors.white,
                    size: 19,
                  ),
                ),

                SizedBox(width: 10),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Administrator',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'ReturnMatch Admin',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Divider(
            height: 1,
            color: Colors.white.withValues(
              alpha: 0.08,
            ),
          ),

          InkWell(
            onTap: _signOut,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(9),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 11,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.logout_rounded,
                    size: 18,
                    color: Colors.white60,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Sign Out',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // NAVIGATION
  // ============================================================

  void _navigateTo(
    AdminPage page,
  ) {
    Widget screen;

    switch (page) {
      case AdminPage.dashboard:
        screen = const AdminDashboardScreen();
        break;

      case AdminPage.items:
        screen = const ItemManagementScreen();
        break;

      case AdminPage.claims:
        screen = const ClaimReviewScreen();
        break;

      case AdminPage.otpCollection:
        screen = const OtpCollectionScreen();
        break;

      case AdminPage.retention:
        screen = const RetentionMonitorScreen();
        break;

      case AdminPage.disposal:
        screen = const DisposalRecordScreen();
        break;

      case AdminPage.audit:
        screen = const AuditLogScreen();
        break;

      case AdminPage.settings:
        screen = const SystemSettingsScreen();
        break;

      case AdminPage.adminManagement:
        screen = const CreateAdminScreen();
        break;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => screen,
      ),
    );
  }

  // ============================================================
  // SIGN OUT
  // ============================================================

  Future<void> _signOut() async {
    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Sign Out',
          ),
          content: const Text(
            'Are you sure you want to sign out of the Admin Portal?',
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
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor:
                    AppColors.adminPrimary,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
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

    if (!mounted) {
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

  // ============================================================
  // PAGE TITLE
  // ============================================================

  String _pageTitle(
    AdminPage page,
  ) {
    switch (page) {
      case AdminPage.dashboard:
        return 'Dashboard';

      case AdminPage.items:
        return 'Item Management';

      case AdminPage.claims:
        return 'Claim Review';

      case AdminPage.otpCollection:
        return 'OTP Collection';

      case AdminPage.retention:
        return 'Retention';

      case AdminPage.disposal:
        return 'Disposal Records';

      case AdminPage.audit:
        return 'Audit Log';

      case AdminPage.settings:
        return 'System Settings';

      case AdminPage.adminManagement:
        return 'Admin Management';
    }
  }
}