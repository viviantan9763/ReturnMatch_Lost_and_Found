import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../widgets/admin/admin_shell.dart';

class SystemSettingsScreen extends StatefulWidget {
  const SystemSettingsScreen({super.key});

  @override
  State<SystemSettingsScreen> createState() =>
      _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends State<SystemSettingsScreen> {
  final TextEditingController _retentionController =
      TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSavingHighValue = false;

  int? _currentRetentionDays;
  String? _errorMessage;

  List<Map<String, dynamic>> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _retentionController.dispose();
    super.dispose();
  }

  // ============================================================
  // LOAD ALL SETTINGS
  // ============================================================

  Future<void> _loadSettings() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      await Future.wait([
        _loadRetentionSetting(),
        _loadHighValueCategories(),
      ]);

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage =
            error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ============================================================
  // GET RETENTION SETTING
  // GET /api/settings/retention
  // ============================================================

  Future<void> _loadRetentionSetting() async {
    final response = await http.get(
      Uri.parse(
        '${AuthService.baseUrl}/settings/retention',
      ),
      headers: AuthService.authenticatedHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(
          response,
          fallback: 'Failed to load retention setting.',
        ),
      );
    }

    final body =
        jsonDecode(response.body) as Map<String, dynamic>;

    final dynamic rawDays =
        body['retention_period_days'] ??
        body['retentionDays'] ??
        body['value'];

    final days = rawDays is int
        ? rawDays
        : int.tryParse(rawDays?.toString() ?? '');

    if (days == null) {
      throw Exception(
        'Invalid retention setting returned by server.',
      );
    }

    if (!mounted) return;

    setState(() {
      _currentRetentionDays = days;
      _retentionController.text = days.toString();
    });
  }

  // ============================================================
  // UPDATE RETENTION SETTING
  // PATCH /api/settings/retention
  // ============================================================

  Future<void> _saveRetentionSetting() async {
    final days =
        int.tryParse(_retentionController.text.trim());

    if (days == null || days < 1 || days > 365) {
      _showMessage(
        'Retention period must be between 1 and 365 days.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final response = await http.patch(
        Uri.parse(
          '${AuthService.baseUrl}/settings/retention',
        ),
        headers: {
          ...AuthService.authenticatedHeaders(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'retention_period_days': days,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception(
          _extractMessage(
            response,
            fallback:
                'Failed to update retention setting.',
          ),
        );
      }

      if (!mounted) return;

      setState(() {
        _currentRetentionDays = days;
      });

      _showMessage(
        'Retention period updated successfully.',
      );
    } catch (error) {
      if (!mounted) return;

      _showMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ============================================================
  // GET HIGH VALUE CATEGORIES
  // GET /api/settings/high-value-categories
  // ============================================================

  Future<void> _loadHighValueCategories() async {
    final response = await http.get(
      Uri.parse(
        '${AuthService.baseUrl}/settings/high-value-categories',
      ),
      headers: AuthService.authenticatedHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(
          response,
          fallback:
              'Failed to load high value categories.',
        ),
      );
    }

    final body =
        jsonDecode(response.body) as Map<String, dynamic>;

    final rawCategories = body['categories'];

    if (rawCategories is! List) {
      throw Exception(
        'Invalid category data returned by server.',
      );
    }

    final categories = rawCategories
        .map(
          (item) => Map<String, dynamic>.from(
            item as Map,
          ),
        )
        .toList();

    if (!mounted) return;

    setState(() {
      _categories = categories;
    });
  }

  // ============================================================
  // CATEGORY HELPERS
  // ============================================================

  List<Map<String, dynamic>> get _highValueCategories {
    return _categories
        .where(
          (category) =>
              category['default_value_tier']
                  ?.toString()
                  .toUpperCase() ==
              'HIGH',
        )
        .toList();
  }

  List<Map<String, dynamic>> get _availableCategories {
    return _categories
        .where(
          (category) =>
              category['default_value_tier']
                  ?.toString()
                  .toUpperCase() !=
              'HIGH',
        )
        .toList();
  }

  int? _categoryId(
    Map<String, dynamic> category,
  ) {
    return int.tryParse(
      category['category_id']?.toString() ?? '',
    );
  }

  // ============================================================
  // SAVE COMPLETE HIGH VALUE CATEGORY LIST
  // PATCH /api/settings/high-value-categories
  // ============================================================

  Future<void> _saveHighValueIds(
    List<int> highValueIds,
  ) async {
    if (_isSavingHighValue) return;

    setState(() {
      _isSavingHighValue = true;
    });

    try {
      final response = await http.patch(
        Uri.parse(
          '${AuthService.baseUrl}/settings/high-value-categories',
        ),
        headers: {
          ...AuthService.authenticatedHeaders(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'high_value_category_ids': highValueIds,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception(
          _extractMessage(
            response,
            fallback:
                'Failed to update high value classification.',
          ),
        );
      }

      final body =
          jsonDecode(response.body) as Map<String, dynamic>;

      final rawCategories = body['categories'];

      if (rawCategories is List) {
        final updatedCategories = rawCategories
            .map(
              (item) => Map<String, dynamic>.from(
                item as Map,
              ),
            )
            .toList();

        if (!mounted) return;

        setState(() {
          _categories = updatedCategories;
        });
      } else {
        await _loadHighValueCategories();
      }

      if (!mounted) return;

      _showMessage(
        'High value classification updated successfully.',
      );
    } catch (error) {
      if (!mounted) return;

      _showMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingHighValue = false;
        });
      }
    }
  }

  // ============================================================
  // REMOVE HIGH VALUE CATEGORY
  // ============================================================

  Future<void> _removeHighValueCategory(
    Map<String, dynamic> category,
  ) async {
    if (_isSavingHighValue) return;

    final categoryId = _categoryId(category);

    if (categoryId == null) {
      _showMessage(
        'Invalid category ID.',
        isError: true,
      );
      return;
    }

    final categoryName =
        category['category_name']?.toString() ??
        'this category';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Remove High Value Classification?',
          ),
          content: Text(
            '$categoryName will return to the default MEDIUM classification.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final ids = _highValueCategories
        .map(_categoryId)
        .whereType<int>()
        .where((id) => id != categoryId)
        .toList();

    await _saveHighValueIds(ids);
  }

  // ============================================================
  // ADD HIGH VALUE CATEGORIES
  // ============================================================

  Future<void> _showAddHighValueDialog() async {
    if (_isSavingHighValue) return;

    final available = _availableCategories;

    if (available.isEmpty) {
      _showMessage(
        'All available categories are already classified as high value.',
      );
      return;
    }

    final selectedIds = <int>{};

    final shouldAdd = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              title: const Text(
                'Add High Value Categories',
              ),
              content: SizedBox(
                width: 480,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 420,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: available.length,
                    separatorBuilder: (_, __) =>
                        const Divider(
                      height: 1,
                    ),
                    itemBuilder: (context, index) {
                      final category =
                          available[index];

                      final id =
                          _categoryId(category);

                      final name =
                          category['category_name']
                                  ?.toString() ??
                              'Unknown Category';

                      if (id == null) {
                        return ListTile(
                          contentPadding:
                              EdgeInsets.zero,
                          title: Text(name),
                          subtitle: const Text(
                            'Invalid category ID',
                          ),
                        );
                      }

                      return CheckboxListTile(
                        value:
                            selectedIds.contains(id),
                        controlAffinity:
                            ListTileControlAffinity
                                .leading,
                        contentPadding:
                            EdgeInsets.zero,
                        activeColor:
                            AppColors.adminPrimary,
                        title: Text(
                          name,
                          style: const TextStyle(
                            color:
                                AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight:
                                FontWeight.w600,
                          ),
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            if (value == true) {
                              selectedIds.add(id);
                            } else {
                              selectedIds.remove(id);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      false,
                    );
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        AppColors.adminPrimary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: selectedIds.isEmpty
                      ? null
                      : () {
                          Navigator.pop(
                            dialogContext,
                            true,
                          );
                        },
                  child: const Text(
                    'Add Selected',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldAdd != true ||
        selectedIds.isEmpty) {
      return;
    }

    final existingIds = _highValueCategories
        .map(_categoryId)
        .whereType<int>()
        .toSet();

    existingIds.addAll(selectedIds);

    final updatedIds = existingIds.toList()
      ..sort();

    await _saveHighValueIds(
      updatedIds,
    );
  }

  // ============================================================
  // PAGE
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedPage: AdminPage.settings,
      child: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.adminPrimary,
                ),
              )
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 1050,
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              _pageHeader(),

              const SizedBox(height: 28),

              if (_errorMessage != null) ...[
                _errorPanel(),
                const SizedBox(height: 20),
              ],

              _sectionHeading(
                title: 'Retention Policy',
                subtitle:
                    'Configure how long physically received items remain in storage before becoming due for disposal.',
              ),

              const SizedBox(height: 12),

              _retentionCard(),

              const SizedBox(height: 30),

              _sectionHeading(
                title: 'Item Classification',
                subtitle:
                    'Configure system-wide item classification rules.',
              ),

              const SizedBox(height: 12),

              _highValueCard(),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _pageHeader() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.adminSoft,
            borderRadius:
                BorderRadius.circular(9),
          ),
          child: const Icon(
            Icons.settings_outlined,
            color: AppColors.adminPrimary,
            size: 24,
          ),
        ),

        const SizedBox(width: 15),

        const Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                'System Settings',
                style: TextStyle(
                  color:
                      AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight:
                      FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Manage system-wide ReturnMatch policies and classification rules.',
                style: TextStyle(
                  color:
                      AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SECTION HEADING
  // ============================================================

  Widget _sectionHeading({
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // RETENTION
  // ============================================================

  Widget _retentionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color:
                      AppColors.adminSoft,
                  borderRadius:
                      BorderRadius.circular(
                    8,
                  ),
                ),
                child: const Icon(
                  Icons.schedule_outlined,
                  color:
                      AppColors.adminPrimary,
                  size: 22,
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Default Retention Period',
                      style: TextStyle(
                        color:
                            AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight:
                            FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      _currentRetentionDays ==
                              null
                          ? 'Current setting unavailable'
                          : 'Current policy: $_currentRetentionDays days',
                      style: const TextStyle(
                        color: AppColors
                            .textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          const Divider(
            height: 1,
            color: AppColors.border,
          ),

          const SizedBox(height: 20),

          const Text(
            'Retention Period',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 7),

          const Text(
            'This period starts automatically when an administrator confirms that a found item has been physically received by the Lost & Found Office.',
            style: TextStyle(
              color:
                  AppColors.textSecondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),

          const SizedBox(height: 14),

          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment:
                WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: TextField(
                  controller:
                      _retentionController,
                  enabled: !_isSaving,
                  keyboardType:
                      TextInputType.number,
                  decoration:
                      InputDecoration(
                    suffixText: 'days',
                    filled: true,
                    fillColor:
                        AppColors.background,
                    border:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius
                              .circular(8),
                      borderSide:
                          const BorderSide(
                        color:
                            AppColors.border,
                      ),
                    ),
                    enabledBorder:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius
                              .circular(8),
                      borderSide:
                          const BorderSide(
                        color:
                            AppColors.border,
                      ),
                    ),
                    focusedBorder:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius
                              .circular(8),
                      borderSide:
                          const BorderSide(
                        color: AppColors
                            .adminPrimary,
                      ),
                    ),
                  ),
                ),
              ),

              FilledButton.icon(
                onPressed: _isSaving
                    ? null
                    : _saveRetentionSetting,
                style:
                    FilledButton.styleFrom(
                  backgroundColor:
                      AppColors.adminPrimary,
                  foregroundColor:
                      Colors.white,
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 20,
                    vertical: 17,
                  ),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                          color:
                              Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.save_outlined,
                        size: 18,
                      ),
                label: Text(
                  _isSaving
                      ? 'Saving...'
                      : 'Save Changes',
                  style: const TextStyle(
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          const Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 17,
                color:
                    AppColors.textSecondary,
              ),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Changing this setting affects the retention period used when new items are received. Existing retention records keep their recorded dates.',
                  style: TextStyle(
                    color: AppColors
                        .textSecondary,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HIGH VALUE CLASSIFICATION
  // ============================================================

  Widget _highValueCard() {
    final highValueCategories =
        _highValueCategories;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color:
                      AppColors.adminSoft,
                  borderRadius:
                      BorderRadius.circular(
                    8,
                  ),
                ),
                child: const Icon(
                  Icons
                      .workspace_premium_outlined,
                  color:
                      AppColors.adminPrimary,
                  size: 22,
                ),
              ),

              const SizedBox(width: 14),

              const Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      'High Value Classification',
                      style: TextStyle(
                        color: AppColors
                            .textPrimary,
                        fontSize: 16,
                        fontWeight:
                            FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Manage categories that require enhanced ownership verification. Categories not included here are automatically classified as MEDIUM.',
                      style: TextStyle(
                        color: AppColors
                            .textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          const Divider(
            height: 1,
            color: AppColors.border,
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              const Expanded(
                child: Text(
                  'High Value Categories',
                  style: TextStyle(
                    color: AppColors
                        .textPrimary,
                    fontSize: 13,
                    fontWeight:
                        FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${highValueCategories.length} selected',
                style: const TextStyle(
                  color: AppColors
                      .textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (highValueCategories.isEmpty)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color:
                    AppColors.background,
                borderRadius:
                    BorderRadius.circular(
                  8,
                ),
                border: Border.all(
                  color: AppColors.border,
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons
                        .info_outline_rounded,
                    size: 18,
                    color: AppColors
                        .textSecondary,
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'No high value categories are currently configured. All categories will default to MEDIUM.',
                      style: TextStyle(
                        color: AppColors
                            .textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppColors.border,
                ),
                borderRadius:
                    BorderRadius.circular(
                  8,
                ),
              ),
              child: Column(
                children: [
                  for (
                    int i = 0;
                    i <
                        highValueCategories
                            .length;
                    i++
                  ) ...[
                    _highValueCategoryRow(
                      highValueCategories[i],
                    ),
                    if (i <
                        highValueCategories
                                .length -
                            1)
                      const Divider(
                        height: 1,
                        color:
                            AppColors.border,
                      ),
                  ],
                ],
              ),
            ),

          const SizedBox(height: 16),

          OutlinedButton.icon(
            onPressed:
                _isSavingHighValue
                    ? null
                    : _showAddHighValueDialog,
            icon: _isSavingHighValue
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.add_rounded,
                    size: 18,
                  ),
            label: Text(
              _isSavingHighValue
                  ? 'Updating...'
                  : 'Add High Value Category',
            ),
            style:
                OutlinedButton.styleFrom(
              foregroundColor:
                  AppColors.adminPrimary,
              side: const BorderSide(
                color:
                    AppColors.adminPrimary,
              ),
              padding:
                  const EdgeInsets
                      .symmetric(
                horizontal: 18,
                vertical: 14,
              ),
            ),
          ),

          const SizedBox(height: 14),

          const Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shield_outlined,
                size: 17,
                color:
                    AppColors.textSecondary,
              ),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Removing a category from this list returns its default classification to MEDIUM. Individual items cannot be manually assigned a value tier.',
                  style: TextStyle(
                    color: AppColors
                        .textSecondary,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _highValueCategoryRow(
    Map<String, dynamic> category,
  ) {
    final name =
        category['category_name']
                ?.toString() ??
            'Unknown Category';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 11,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.adminSoft,
              borderRadius:
                  BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons
                  .workspace_premium_outlined,
              color:
                  AppColors.adminPrimary,
              size: 17,
            ),
          ),

          const SizedBox(width: 11),

          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                color:
                    AppColors.textPrimary,
                fontSize: 13,
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ),

          Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: AppColors.adminSoft,
              borderRadius:
                  BorderRadius.circular(
                20,
              ),
            ),
            child: const Text(
              'HIGH',
              style: TextStyle(
                color:
                    AppColors.adminPrimary,
                fontSize: 10,
                fontWeight:
                    FontWeight.w800,
              ),
            ),
          ),

          const SizedBox(width: 8),

          IconButton(
            tooltip:
                'Remove from High Value',
            onPressed:
                _isSavingHighValue
                    ? null
                    : () {
                        _removeHighValueCategory(
                          category,
                        );
                      },
            icon: const Icon(
              Icons.close_rounded,
              size: 19,
            ),
            color: AppColors.danger,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ERROR
  // ============================================================

  Widget _errorPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.red.withValues(
          alpha: 0.05,
        ),
        borderRadius:
            BorderRadius.circular(8),
        border: Border.all(
          color: Colors.red.withValues(
            alpha: 0.20,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: Colors.red.shade700,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(
                color:
                    Colors.red.shade700,
                fontSize: 12,
              ),
            ),
          ),
          TextButton(
            onPressed: _loadSettings,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Colors.red.shade700
            : AppColors.adminDark,
      ),
    );
  }

  static String _extractMessage(
    http.Response response, {
    required String fallback,
  }) {
    try {
      final body =
          jsonDecode(response.body);

      if (body is Map<String, dynamic> &&
          body['message'] != null) {
        return body['message'].toString();
      }
    } catch (_) {}

    return fallback;
  }
}