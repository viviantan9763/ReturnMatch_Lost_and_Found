import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../widgets/student/student_shell.dart';

import 'report_lost_screen.dart';
import 'report_found_screen.dart';
import 'search_item_screen.dart';
import 'claim_item_screen.dart';
import 'my_claims_screen.dart';

class StudentHomeScreen extends StatelessWidget {
  const StudentHomeScreen({super.key});

  // =========================================================
  // NAVIGATION
  // =========================================================

  void _goTo(
    BuildContext context,
    Widget page,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => page,
      ),
    );
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return StudentShell(
      selectedPage: StudentPage.home,
      title: 'Home',
      child: Container(
        color: AppColors.background,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (
              context,
              constraints,
            ) {
              return Center(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(
                    maxWidth: 1100,
                  ),
                  child: ListView(
                    padding:
                        const EdgeInsets.all(
                      20,
                    ),
                    children: [
                      _welcomePanel(),

                      const SizedBox(
                        height: 18,
                      ),

                      _searchBar(
                        context,
                      ),

                      const SizedBox(
                        height: 24,
                      ),

                      // =======================================
                      // QUICK ACTIONS
                      // =======================================

                      const _SectionHeading(
                        title:
                            'Quick Actions',
                        subtitle:
                            'Common lost-and-found services',
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      _quickActions(
                        context,
                        constraints.maxWidth,
                      ),

                      const SizedBox(
                        height: 28,
                      ),

                      // =======================================
                      // CLAIM WORKFLOW
                      // =======================================

                      const _SectionHeading(
                        title:
                            'Claim & Collection Process',
                        subtitle:
                            'Secure ownership verification for found items',
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      _claimProcessPanel(),

                      const SizedBox(
                        height: 28,
                      ),

                      // =======================================
                      // AI MATCH
                      // =======================================

                      const _SectionHeading(
                        title:
                            'AI Match Suggestions',
                        subtitle:
                            'Potential found-item matches based on your reports',
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      // =======================================
                      // DEMO DATA ONLY
                      //
                      // Real MATCH_RESULT API will replace
                      // these cards during AI integration.
                      // =======================================

                      _matchCard(
                        context,
                        5,
                        'Black Mobile Phone',
                        'Library Level 2',
                        '95%',
                        'HIGH',
                        Icons
                            .smartphone_outlined,
                      ),

                      _matchCard(
                        context,
                        7,
                        'Blue Backpack',
                        'Student Lounge',
                        '88%',
                        'MEDIUM',
                        Icons
                            .backpack_outlined,
                      ),

                      _matchCard(
                        context,
                        5,
                        'Wireless Earbuds',
                        'Computer Lab',
                        '82%',
                        'HIGH',
                        Icons
                            .headphones_outlined,
                      ),

                      const SizedBox(
                        height: 20,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // =========================================================
  // WELCOME PANEL
  // =========================================================

  Widget _welcomePanel() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Container(
            width: 5,
            height: 64,
            decoration: BoxDecoration(
              color:
                  AppColors.studentPrimary,
              borderRadius:
                  BorderRadius.circular(
                2,
              ),
            ),
          ),

          const SizedBox(
            width: 16,
          ),

          const Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome to ReturnMatch',
                  style: TextStyle(
                    color:
                        AppColors.textPrimary,
                    fontSize: 21,
                    fontWeight:
                        FontWeight.w700,
                  ),
                ),

                SizedBox(
                  height: 7,
                ),

                Text(
                  'Report, search and claim lost property with AI-assisted item matching.',
                  style: TextStyle(
                    color: AppColors
                        .textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // SEARCH BAR
  // =========================================================

  Widget _searchBar(
    BuildContext context,
  ) {
    return TextField(
      readOnly: true,
      onTap: () {
        _goTo(
          context,
          const SearchItemScreen(),
        );
      },
      decoration: InputDecoration(
        hintText:
            'Search by item name, category or location',
        hintStyle:
            const TextStyle(
          color:
              AppColors.textSecondary,
        ),
        prefixIcon:
            const Icon(
          Icons.search,
          color:
              AppColors.studentPrimary,
        ),
        suffixIcon:
            const Icon(
          Icons.tune,
          color:
              AppColors.textSecondary,
        ),
        filled: true,
        fillColor: Colors.white,
        border:
            OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(
            8,
          ),
          borderSide:
              const BorderSide(
            color: AppColors.border,
          ),
        ),
        enabledBorder:
            OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(
            8,
          ),
          borderSide:
              const BorderSide(
            color: AppColors.border,
          ),
        ),
        focusedBorder:
            OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(
            8,
          ),
          borderSide:
              const BorderSide(
            color: AppColors
                .studentPrimary,
          ),
        ),
      ),
    );
  }

  // =========================================================
  // QUICK ACTIONS
  // =========================================================

  Widget _quickActions(
    BuildContext context,
    double width,
  ) {
    final actions = [
      (
        'Report Lost Item',
        'Create a lost-item report',
        Icons.search_off_outlined,
        const ReportLostScreen(),
      ),
      (
        'Report Found Item',
        'Register a found item',
        Icons.inventory_2_outlined,
        const ReportFoundScreen(),
      ),
      (
        'Search Matches',
        'Search AI-assisted matches',
        Icons.manage_search_outlined,
        const SearchItemScreen(),
      ),
      (
        'My Claims',
        'Review your claim requests',
        Icons.verified_user_outlined,
        const MyClaimsScreen(),
      ),
    ];

    final columns =
        width >= 760 ? 4 : 2;

    return GridView.builder(
      shrinkWrap: true,
      physics:
          const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate:
          SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio:
            width >= 760
                ? 1.35
                : 1.25,
      ),
      itemBuilder: (
        context,
        index,
      ) {
        final action =
            actions[index];

        return _actionCard(
          context: context,
          title: action.$1,
          subtitle: action.$2,
          icon: action.$3,
          page: action.$4,
        );
      },
    );
  }

  Widget _actionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget page,
  }) {
    return InkWell(
      borderRadius:
          BorderRadius.circular(8),
      onTap: () {
        _goTo(
          context,
          page,
        );
      },
      child: Container(
        padding:
            const EdgeInsets.all(
          16,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(
            8,
          ),
          border: Border.all(
            color: AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color:
                    AppColors.studentSoft,
                borderRadius:
                    BorderRadius.circular(
                  6,
                ),
              ),
              child: Icon(
                icon,
                color:
                    AppColors.studentPrimary,
                size: 21,
              ),
            ),

            const Spacer(),

            Text(
              title,
              style:
                  const TextStyle(
                fontSize: 14,
                fontWeight:
                    FontWeight.w700,
                color:
                    AppColors.textPrimary,
              ),
            ),

            const SizedBox(
              height: 4,
            ),

            Text(
              subtitle,
              style:
                  const TextStyle(
                fontSize: 11,
                color: AppColors
                    .textSecondary,
              ),
              maxLines: 2,
              overflow:
                  TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // CLAIM PROCESS
  // =========================================================

  Widget _claimProcessPanel() {
    return Container(
      padding:
          const EdgeInsets.all(
        18,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(
          8,
        ),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Column(
        children: [
          _processStep(
            number: '1',
            icon:
                Icons.edit_document,
            title:
                'Submit Claim',
            subtitle:
                'Provide a claim reason and ownership details.',
          ),

          _processDivider(),

          _processStep(
            number: '2',
            icon:
                Icons.security_outlined,
            title:
                'Security Verification',
            subtitle:
                'Answer item-specific security questions.',
          ),

          _processDivider(),

          _processStep(
            number: '3',
            icon: Icons
                .admin_panel_settings_outlined,
            title:
                'Administrator Review',
            subtitle:
                'An administrator verifies the ownership evidence.',
          ),

          _processDivider(),

          _processStep(
            number: '4',
            icon:
                Icons.password_outlined,
            title:
                'OTP Collection',
            subtitle:
                'Approved claims receive a one-time collection code.',
          ),

          _processDivider(),

          _processStep(
            number: '5',
            icon: Icons
                .check_circle_outline,
            title:
                'Item Collected',
            subtitle:
                'Admin verifies the OTP and completes the collection.',
          ),
        ],
      ),
    );
  }

  Widget _processStep({
    required String number,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment:
              Alignment.center,
          decoration: BoxDecoration(
            color:
                AppColors.studentSoft,
            borderRadius:
                BorderRadius.circular(
              17,
            ),
          ),
          child: Text(
            number,
            style:
                const TextStyle(
              color: AppColors
                  .studentPrimary,
              fontWeight:
                  FontWeight.w800,
            ),
          ),
        ),

        const SizedBox(
          width: 12,
        ),

        Icon(
          icon,
          size: 22,
          color:
              AppColors.studentPrimary,
        ),

        const SizedBox(
          width: 12,
        ),

        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    const TextStyle(
                  color: AppColors
                      .textPrimary,
                  fontWeight:
                      FontWeight.w700,
                  fontSize: 13,
                ),
              ),

              const SizedBox(
                height: 3,
              ),

              Text(
                subtitle,
                style:
                    const TextStyle(
                  color: AppColors
                      .textSecondary,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _processDivider() {
    return Container(
      height: 18,
      margin:
          const EdgeInsets.only(
        left: 16,
      ),
      alignment:
          Alignment.centerLeft,
      child: Container(
        width: 2,
        height: 18,
        color: AppColors.border,
      ),
    );
  }

  // =========================================================
  // AI MATCH CARD
  // =========================================================

  Widget _matchCard(
    BuildContext context,
    int itemId,
    String itemName,
    String location,
    String matchRate,
    String valueTier,
    IconData icon,
  ) {
    return InkWell(
      borderRadius:
          BorderRadius.circular(8),
      onTap: () {
        _goTo(
          context,
          ClaimItemScreen(
            itemId: itemId,
            itemName: itemName,
            valueTier: valueTier,
          ),
        );
      },
      child: Container(
        margin:
            const EdgeInsets.only(
          bottom: 10,
        ),
        padding:
            const EdgeInsets.all(
          15,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(
            8,
          ),
          border: Border.all(
            color: AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color:
                    AppColors.studentSoft,
                borderRadius:
                    BorderRadius.circular(
                  6,
                ),
              ),
              child: Icon(
                icon,
                color:
                    AppColors.studentPrimary,
              ),
            ),

            const SizedBox(
              width: 14,
            ),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    itemName,
                    style:
                        const TextStyle(
                      fontSize: 14,
                      fontWeight:
                          FontWeight.w700,
                      color: AppColors
                          .textPrimary,
                    ),
                  ),

                  const SizedBox(
                    height: 4,
                  ),

                  Row(
                    children: [
                      const Icon(
                        Icons
                            .location_on_outlined,
                        size: 15,
                        color: AppColors
                            .textSecondary,
                      ),

                      const SizedBox(
                        width: 4,
                      ),

                      Expanded(
                        child: Text(
                          location,
                          style:
                              const TextStyle(
                            fontSize: 12,
                            color: AppColors
                                .textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 5,
                  ),

                  Text(
                    valueTier == 'HIGH'
                        ? 'High-value item • Enhanced verification required'
                        : 'Standard verification',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          FontWeight.w600,
                      color:
                          valueTier ==
                                  'HIGH'
                              ? Colors.red
                              : AppColors
                                  .textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(
              width: 10,
            ),

            Container(
              padding:
                  const EdgeInsets
                      .symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration:
                  BoxDecoration(
                color:
                    AppColors.studentSoft,
                borderRadius:
                    BorderRadius.circular(
                  4,
                ),
              ),
              child: Text(
                '$matchRate match',
                style:
                    const TextStyle(
                  color:
                      AppColors.studentDark,
                  fontSize: 11,
                  fontWeight:
                      FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================
// SECTION HEADING
// ===========================================================

class _SectionHeading
    extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeading({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style:
              const TextStyle(
            fontSize: 17,
            fontWeight:
                FontWeight.w700,
            color:
                AppColors.textPrimary,
          ),
        ),

        const SizedBox(
          height: 3,
        ),

        Text(
          subtitle,
          style:
              const TextStyle(
            fontSize: 12,
            color: AppColors
                .textSecondary,
          ),
        ),
      ],
    );
  }
}