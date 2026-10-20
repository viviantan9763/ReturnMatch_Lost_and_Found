import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';

import '../../screens/student/student_home_screen.dart';
import '../../screens/student/report_selection_screen.dart';
import '../../screens/student/search_item_screen.dart';
import '../../screens/student/my_claims_screen.dart';
import '../../screens/student/profile_screen.dart';

enum StudentPage {
  home,
  search,
  report,
  claims,
  notifications,
  profile,
}

class StudentShell extends StatefulWidget {
  final StudentPage selectedPage;
  final Widget child;
  final String? title;

  const StudentShell({
    super.key,
    required this.selectedPage,
    required this.child,
    this.title,
  });

  @override
  State<StudentShell> createState() =>
      _StudentShellState();
}

class _StudentShellState
    extends State<StudentShell> {
  bool _isExpanded = true;

  static const double _expandedWidth = 240;
  static const double _collapsedWidth = 76;
  static const double _mobileBreakpoint = 850;

  void _toggleSidebar() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  void _navigateTo(
    StudentPage page,
  ) {
    if (page == widget.selectedPage) {
      return;
    }

    Widget destination;

    switch (page) {
      case StudentPage.home:
        destination =
            const StudentHomeScreen();
        break;

      case StudentPage.search:
        destination =
            const SearchItemScreen();
        break;

      case StudentPage.report:
        destination =
            const ReportSelectionScreen();
        break;

      case StudentPage.claims:
        destination =
            const MyClaimsScreen();
        break;

      case StudentPage.profile:
        destination =
            const ProfileScreen();
        break;

      case StudentPage.notifications:
        _showNotifications();
        return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => destination,
      ),
    );
  }

  void _showNotifications() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape:
          const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(18),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.all(20),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons
                          .notifications_outlined,
                      color: AppColors
                          .studentPrimary,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Notifications',
                      style: TextStyle(
                        color: AppColors
                            .textPrimary,
                        fontSize: 18,
                        fontWeight:
                            FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Notifications will appear here when the notification module is connected.',
                  style: TextStyle(
                    color: AppColors
                        .textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _signOut() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title:
              const Text('Sign Out'),
          content: const Text(
            'Are you sure you want to sign out?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child:
                  const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );

                // We will connect this to your
                // existing AuthService logout flow
                // after checking your login screen.
                Navigator.of(context)
                    .popUntil(
                  (route) =>
                      route.isFirst,
                );
              },
              style:
                  ElevatedButton.styleFrom(
                backgroundColor:
                    AppColors.studentPrimary,
                foregroundColor:
                    Colors.white,
              ),
              child:
                  const Text('Sign Out'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final isMobile =
            constraints.maxWidth <
                _mobileBreakpoint;

        if (isMobile) {
          return _buildMobileLayout();
        }

        return _buildDesktopLayout();
      },
    );
  }

  // =========================================================
  // DESKTOP
  // =========================================================

  Widget _buildDesktopLayout() {
    return Scaffold(
      backgroundColor:
          AppColors.background,
      body: Row(
        children: [
          AnimatedContainer(
            duration:
                const Duration(
              milliseconds: 220,
            ),
            curve: Curves.easeInOut,
            width: _isExpanded
                ? _expandedWidth
                : _collapsedWidth,
            child: _sidebar(
              expanded: _isExpanded,
              mobile: false,
            ),
          ),

          Expanded(
            child: Column(
              children: [
                _topBar(
                  showMenuButton: false,
                ),
                Expanded(
                  child: widget.child,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // MOBILE
  // =========================================================

  Widget _buildMobileLayout() {
    return Scaffold(
      backgroundColor:
          AppColors.background,
      drawer: Drawer(
        width: 270,
        child: _sidebar(
          expanded: true,
          mobile: true,
        ),
      ),
      appBar: AppBar(
        backgroundColor:
            AppColors.studentPrimary,
        foregroundColor:
            Colors.white,
        elevation: 0,
        title: Text(
          widget.title ??
              _pageTitle(
                widget.selectedPage,
              ),
          style:
              const TextStyle(
            fontWeight:
                FontWeight.w800,
          ),
        ),
      ),
      body: widget.child,
    );
  }

  // =========================================================
  // DESKTOP TOP BAR
  // =========================================================

  Widget _topBar({
    required bool showMenuButton,
  }) {
    return Container(
      height: 64,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 20,
      ),
      decoration:
          const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: AppColors.border,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: _isExpanded
                ? 'Collapse navigation'
                : 'Expand navigation',
            onPressed:
                _toggleSidebar,
            icon: Icon(
              _isExpanded
                  ? Icons
                      .menu_open_rounded
                  : Icons.menu_rounded,
              color:
                  AppColors.studentPrimary,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Text(
              widget.title ??
                  _pageTitle(
                    widget.selectedPage,
                  ),
              style:
                  const TextStyle(
                color:
                    AppColors.textPrimary,
                fontSize: 18,
                fontWeight:
                    FontWeight.w800,
              ),
            ),
          ),

          IconButton(
            tooltip:
                'Notifications',
            onPressed:
                _showNotifications,
            icon: const Icon(
              Icons
                  .notifications_none_rounded,
              color: AppColors
                  .textSecondary,
            ),
          ),

          const SizedBox(width: 4),

          IconButton(
            tooltip: 'Profile',
            onPressed: () {
              _navigateTo(
                StudentPage.profile,
              );
            },
            icon: const Icon(
              Icons.person_outline,
              color: AppColors
                  .textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // SIDEBAR
  // =========================================================

  Widget _sidebar({
    required bool expanded,
    required bool mobile,
  }) {
    return Container(
      color:
          AppColors.studentDark,
      child: SafeArea(
        child: Column(
          children: [
            _sidebarHeader(
              expanded,
            ),

            const SizedBox(height: 14),

            _navItem(
              page:
                  StudentPage.home,
              icon:
                  Icons.home_outlined,
              activeIcon:
                  Icons.home_rounded,
              label: 'Home',
              expanded: expanded,
              mobile: mobile,
            ),

            _navItem(
              page:
                  StudentPage.search,
              icon:
                  Icons.search_outlined,
              activeIcon:
                  Icons.search_rounded,
              label: 'Search Items',
              expanded: expanded,
              mobile: mobile,
            ),

            _navItem(
              page:
                  StudentPage.report,
              icon:
                  Icons.add_box_outlined,
              activeIcon:
                  Icons.add_box_rounded,
              label: 'Report Item',
              expanded: expanded,
              mobile: mobile,
            ),

            _navItem(
              page:
                  StudentPage.claims,
              icon:
                  Icons
                      .verified_user_outlined,
              activeIcon:
                  Icons
                      .verified_user_rounded,
              label: 'My Claims',
              expanded: expanded,
              mobile: mobile,
            ),

            _navItem(
              page:
                  StudentPage.notifications,
              icon:
                  Icons
                      .notifications_none_outlined,
              activeIcon:
                  Icons.notifications,
              label: 'Notifications',
              expanded: expanded,
              mobile: mobile,
            ),

            const SizedBox(height: 12),

            if (expanded)
              const Padding(
                padding:
                    EdgeInsets.fromLTRB(
                  18,
                  8,
                  18,
                  8,
                ),
                child: Align(
                  alignment:
                      Alignment.centerLeft,
                  child: Text(
                    'ACCOUNT',
                    style:
                        TextStyle(
                      color:
                          Colors.white54,
                      fontSize: 10,
                      fontWeight:
                          FontWeight.w800,
                      letterSpacing:
                          1.2,
                    ),
                  ),
                ),
              )
            else
              const Divider(
                color:
                    Colors.white12,
                indent: 18,
                endIndent: 18,
              ),

            _navItem(
              page:
                  StudentPage.profile,
              icon:
                  Icons.person_outline,
              activeIcon:
                  Icons.person,
              label: 'Profile',
              expanded: expanded,
              mobile: mobile,
            ),

            const Spacer(),

            _signOutItem(
              expanded,
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _sidebarHeader(
    bool expanded,
  ) {
    return Container(
      height: 72,
      padding:
          EdgeInsets.symmetric(
        horizontal:
            expanded ? 18 : 12,
      ),
      child: Row(
        mainAxisAlignment:
            expanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment:
                Alignment.center,
            decoration:
                BoxDecoration(
              color:
                  AppColors.studentPrimary,
              borderRadius:
                  BorderRadius.circular(
                8,
              ),
            ),
            child:
                const Icon(
              Icons
                  .find_in_page_outlined,
              color:
                  Colors.white,
              size: 21,
            ),
          ),

          if (expanded) ...[
            const SizedBox(width: 12),

            const Expanded(
              child: Column(
                mainAxisAlignment:
                    MainAxisAlignment
                        .center,
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Text(
                    'ReturnMatch',
                    style:
                        TextStyle(
                      color:
                          Colors.white,
                      fontSize: 16,
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'STUDENT / STAFF',
                    style:
                        TextStyle(
                      color:
                          Colors.white60,
                      fontSize: 9,
                      fontWeight:
                          FontWeight.w700,
                      letterSpacing:
                          0.8,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _navItem({
    required StudentPage page,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool expanded,
    required bool mobile,
  }) {
    final selected =
        widget.selectedPage == page;

    return Padding(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 3,
      ),
      child: Tooltip(
        message:
            expanded ? '' : label,
        child: Material(
          color: selected
              ? AppColors.studentPrimary
              : Colors.transparent,
          borderRadius:
              BorderRadius.circular(
            8,
          ),
          child: InkWell(
            borderRadius:
                BorderRadius.circular(
              8,
            ),
            onTap: () {
              if (mobile) {
                Navigator.pop(
                  context,
                );
              }

              _navigateTo(page);
            },
            child: Container(
              height: 46,
              padding:
                  EdgeInsets.symmetric(
                horizontal:
                    expanded ? 12 : 0,
              ),
              child: Row(
                mainAxisAlignment:
                    expanded
                        ? MainAxisAlignment
                            .start
                        : MainAxisAlignment
                            .center,
                children: [
                  Icon(
                    selected
                        ? activeIcon
                        : icon,
                    color: selected
                        ? Colors.white
                        : Colors.white70,
                    size: 21,
                  ),

                  if (expanded) ...[
                    const SizedBox(
                      width: 12,
                    ),
                    Expanded(
                      child: Text(
                        label,
                        style:
                            TextStyle(
                          color: selected
                              ? Colors.white
                              : Colors
                                  .white70,
                          fontSize: 13,
                          fontWeight:
                              selected
                                  ? FontWeight
                                      .w800
                                  : FontWeight
                                      .w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _signOutItem(
    bool expanded,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
      ),
      child: Tooltip(
        message:
            expanded
                ? ''
                : 'Sign Out',
        child: Material(
          color:
              Colors.transparent,
          borderRadius:
              BorderRadius.circular(
            8,
          ),
          child: InkWell(
            borderRadius:
                BorderRadius.circular(
              8,
            ),
            onTap: _signOut,
            child: Container(
              height: 46,
              padding:
                  EdgeInsets.symmetric(
                horizontal:
                    expanded ? 12 : 0,
              ),
              child: Row(
                mainAxisAlignment:
                    expanded
                        ? MainAxisAlignment
                            .start
                        : MainAxisAlignment
                            .center,
                children: [
                  const Icon(
                    Icons
                        .logout_rounded,
                    color:
                        Colors.white60,
                    size: 21,
                  ),
                  if (expanded) ...[
                    const SizedBox(
                      width: 12,
                    ),
                    const Text(
                      'Sign Out',
                      style:
                          TextStyle(
                        color:
                            Colors.white70,
                        fontSize: 13,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _pageTitle(
    StudentPage page,
  ) {
    switch (page) {
      case StudentPage.home:
        return 'Home';
      case StudentPage.search:
        return 'Search Items';
      case StudentPage.report:
        return 'Report Item';
      case StudentPage.claims:
        return 'My Claims';
      case StudentPage.notifications:
        return 'Notifications';
      case StudentPage.profile:
        return 'Profile';
    }
  }
}