import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../widgets/admin/admin_shell.dart';

class ItemManagementScreen extends StatefulWidget {
  const ItemManagementScreen({super.key});

  @override
  State<ItemManagementScreen> createState() =>
      _ItemManagementScreenState();
}

class _ItemManagementScreenState extends State<ItemManagementScreen> {
  static const Color adminBlue = AppColors.adminPrimary;
  static const Color adminDark = AppColors.adminDark;
  static const Color background = AppColors.background;
  static const Color textDark = AppColors.textPrimary;

  // Only real items returned by the backend are stored here.
  final List<Map<String, dynamic>> _items = [];

  bool _isLoading = true;
  String? _errorMessage;

  String _searchQuery = '';
  String _selectedType = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  // ============================================================
  // LOAD REAL ITEMS FROM DATABASE
  // GET /api/items
  // ============================================================

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/items'),
        headers: AuthService.authenticatedHeaders(),
      );

      if (response.statusCode != 200) {
        throw Exception(
          _extractMessage(
            response,
            fallback: 'Failed to load items.',
          ),
        );
      }

      final decoded = jsonDecode(response.body);

      List<dynamic> rawItems = [];

      if (decoded is List) {
        rawItems = decoded;
      } else if (decoded is Map<String, dynamic>) {
        if (decoded['items'] is List) {
          rawItems = decoded['items'] as List<dynamic>;
        }
      }

      final loadedItems = rawItems.map((rawItem) {
        final item = Map<String, dynamic>.from(rawItem as Map);

        final rawStatus =
            item['status']?.toString().toUpperCase() ?? 'ACTIVE';

        final itemType =
            item['item_type']?.toString().toUpperCase() ?? 'UNKNOWN';

        final custodyStatus =
            item['custody_status']?.toString().toUpperCase();

        // MEDIUM is the default tier if no value is returned.
        // The UI does NOT manually change the tier.
        final valueTier =
            item['value_tier']?.toString().toUpperCase() ?? 'MEDIUM';

        return <String, dynamic>{
          'itemId': item['item_id'].toString(),
          'itemName': item['item_name']?.toString() ?? 'Unnamed Item',
          'modelInfo': _nullableText(item['model_info']) ?? 'Not Sure',
          'location':
              _nullableText(item['location']) ?? 'Location not provided',
          'tier': valueTier,
          'rawStatus': rawStatus,
          'itemType': itemType,
          'custodyStatus': custodyStatus,
          'reporterName':
              item['reporter_name']?.toString() ?? 'Unknown Reporter',
          'reportedAt': item['reported_at']?.toString(),
          'eventDate': item['event_date']?.toString(),
          'description': _nullableText(item['description']),
          'colour': _nullableText(item['colour']),
          'categoryId': item['category_id'],
          'categoryName': _nullableText(
            item['category_name'] ?? item['category'],
          ),
          'storageLocation': _nullableText(item['storage_location']),
        };
      }).toList();

      if (!mounted) return;

      setState(() {
        _items
          ..clear()
          ..addAll(loadedItems);

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
  // CONFIRM FOUND ITEM RECEIVED
  // PATCH /api/items/:id/receive
  // ============================================================

  Future<bool> _confirmItemReceived({
    required String itemId,
    required String storageLocation,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('${AuthService.baseUrl}/items/$itemId/receive'),
        headers: {
          ...AuthService.authenticatedHeaders(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'storage_location': storageLocation.trim(),
        }),
      );

      if (response.statusCode == 200) {
        await _loadItems();
        return true;
      }

      _showMessage(
        _extractMessage(
          response,
          fallback: 'Failed to confirm item receipt.',
        ),
        isError: true,
      );

      return false;
    } catch (error) {
      _showMessage(
        'Unable to connect to server: $error',
        isError: true,
      );

      return false;
    }
  }

  // ============================================================
  // FILTERING
  // ============================================================

  List<Map<String, dynamic>> get _filteredItems {
    return _items.where((item) {
      final query = _searchQuery.toLowerCase();

      final matchesSearch =
          item['itemName'].toString().toLowerCase().contains(query) ||
          item['itemId'].toString().toLowerCase().contains(query) ||
          item['location'].toString().toLowerCase().contains(query) ||
          item['reporterName'].toString().toLowerCase().contains(query);

      final matchesType =
          _selectedType == 'ALL' ||
          item['itemType'].toString().toUpperCase() == _selectedType;

      return matchesSearch && matchesType;
    }).toList();
  }

  // ============================================================
  // STATISTICS
  // ============================================================

  int get _foundCount {
    return _items.where((item) {
      return item['itemType'].toString().toUpperCase() == 'FOUND';
    }).length;
  }

  int get _awaitingReceiptCount {
    return _items.where((item) {
      return item['itemType'].toString().toUpperCase() == 'FOUND' &&
          item['custodyStatus'] == 'NOT_RECEIVED';
    }).length;
  }

  int get _highValueCount {
    return _items.where((item) {
      return item['tier'].toString().toUpperCase() == 'HIGH';
    }).length;
  }

  // ============================================================
  // PAGE
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedPage: AdminPage.items,
      child: Container(
        color: background,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding =
                  constraints.maxWidth >= 1100 ? 32.0 : 20.0;

              return Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  24,
                  horizontalPadding,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _pageHeader(),
                    const SizedBox(height: 24),
                    _statisticsSection(),
                    const SizedBox(height: 24),
                    _toolbar(),
                    const SizedBox(height: 18),
                    Expanded(
                      child: _buildItemContent(),
                    ),
                  ],
                ),
              );
            },
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Item Management',
                style: TextStyle(
                  color: textDark,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Review and manage reported lost and found items.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _loadItems,
          icon: const Icon(
            Icons.refresh_rounded,
            size: 19,
          ),
          label: const Text(
            'Refresh',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: adminBlue,
            padding: const EdgeInsets.symmetric(
              horizontal: 17,
              vertical: 15,
            ),
            side: const BorderSide(
              color: AppColors.border,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // STATISTICS
  // ============================================================

  Widget _statisticsSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _statCard(
            title: 'Total Items',
            value: _items.length.toString(),
            icon: Icons.inventory_2_outlined,
          ),
          _statCard(
            title: 'Found Items',
            value: _foundCount.toString(),
            icon: Icons.search_rounded,
          ),
          _statCard(
            title: 'Awaiting Receipt',
            value: _awaitingReceiptCount.toString(),
            icon: Icons.move_to_inbox_outlined,
            highlight: _awaitingReceiptCount > 0,
          ),
          _statCard(
            title: 'High Value',
            value: _highValueCount.toString(),
            icon: Icons.shield_outlined,
          ),
        ];

        if (constraints.maxWidth < 760) {
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: cards.map((card) {
              return SizedBox(
                width: (constraints.maxWidth - 12) / 2,
                child: card,
              );
            }).toList(),
          );
        }

        return Row(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              Expanded(child: cards[i]),
              if (i != cards.length - 1)
                const SizedBox(width: 14),
            ],
          ],
        );
      },
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight
              ? adminBlue.withValues(alpha: 0.35)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: highlight
                  ? adminBlue.withValues(alpha: 0.10)
                  : AppColors.adminSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              size: 23,
              color: adminBlue,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SEARCH + FILTER
  // ============================================================

  Widget _toolbar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 650) {
            return Column(
              children: [
                _searchField(),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _typeFilter(),
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: _searchField(),
              ),
              const SizedBox(width: 16),
              _typeFilter(),
            ],
          );
        },
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      style: const TextStyle(
        fontSize: 14,
        color: textDark,
      ),
      onChanged: (value) {
        setState(() {
          _searchQuery = value.trim();
        });
      },
      decoration: InputDecoration(
        hintText: 'Search by item ID, name, location or reporter',
        hintStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 21,
          color: AppColors.textSecondary,
        ),
        filled: true,
        fillColor: background,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _typeFilter() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'ALL',
          label: Text('All'),
        ),
        ButtonSegment(
          value: 'LOST',
          label: Text('Lost'),
        ),
        ButtonSegment(
          value: 'FOUND',
          label: Text('Found'),
        ),
      ],
      selected: {_selectedType},
      onSelectionChanged: (selection) {
        setState(() {
          _selectedType = selection.first;
        });
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStateProperty.all(
          const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // CONTENT
  // ============================================================

  Widget _buildItemContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: adminBlue,
        ),
      );
    }

    if (_errorMessage != null) {
      return _errorState();
    }

    if (_filteredItems.isEmpty) {
      return _emptyState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Items',
                style: TextStyle(
                  color: textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '${_filteredItems.length} item(s)',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.border,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 850) {
                  return _desktopTable();
                }

                return _compactList();
              },
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // DESKTOP TABLE
  // ============================================================

  Widget _desktopTable() {
    return Column(
      children: [
        _tableHeader(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadItems,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _filteredItems.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                color: AppColors.border,
              ),
              itemBuilder: (context, index) {
                return _tableRow(
                  _filteredItems[index],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _tableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 14,
      ),
      color: AppColors.adminSoft,
      child: const Row(
        children: [
          Expanded(
            flex: 4,
            child: _TableLabel('ITEM'),
          ),
          Expanded(
            flex: 2,
            child: _TableLabel('TYPE'),
          ),
          Expanded(
            flex: 2,
            child: _TableLabel('VALUE TIER'),
          ),
          Expanded(
            flex: 3,
            child: _TableLabel('CUSTODY'),
          ),
          Expanded(
            flex: 2,
            child: _TableLabel('STATUS'),
          ),
          SizedBox(
            width: 55,
            child: _TableLabel(''),
          ),
        ],
      ),
    );
  }

  Widget _tableRow(Map<String, dynamic> item) {
    return InkWell(
      onTap: () => _showItemDetails(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: _itemIdentity(item),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _typeBadge(
                  item['itemType'].toString(),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _tierBadge(
                  item['tier'].toString(),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: _custodyCell(item),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _statusBadge(
                  item['rawStatus'].toString(),
                ),
              ),
            ),
            SizedBox(
              width: 55,
              child: IconButton(
                tooltip: 'View Details',
                onPressed: () {
                  _showItemDetails(item);
                },
                icon: const Icon(
                  Icons.chevron_right_rounded,
                  size: 24,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemIdentity(Map<String, dynamic> item) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.adminSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getItemIcon(
              item['itemName'].toString(),
            ),
            size: 22,
            color: adminBlue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['itemName'].toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: textDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '#${item['itemId']} · ${item['location']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SMALL SCREEN LIST
  // ============================================================

  Widget _compactList() {
    return RefreshIndicator(
      onRefresh: _loadItems,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _filteredItems.length,
        separatorBuilder: (_, __) => const Divider(
          height: 1,
          color: AppColors.border,
        ),
        itemBuilder: (context, index) {
          final item = _filteredItems[index];

          return InkWell(
            onTap: () => _showItemDetails(item),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _itemIdentity(item),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 24,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _typeBadge(
                        item['itemType'].toString(),
                      ),
                      _tierBadge(
                        item['tier'].toString(),
                      ),
                      _custodyBadge(item),
                      _statusBadge(
                        item['rawStatus'].toString(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // BADGES
  // ============================================================

  Widget _typeBadge(String type) {
    final isFound = type.toUpperCase() == 'FOUND';

    return _badge(
      label: isFound ? 'Found' : 'Lost',
      foreground:
          isFound ? AppColors.success : Colors.orange.shade800,
      background: isFound
          ? AppColors.success.withValues(alpha: 0.09)
          : Colors.orange.withValues(alpha: 0.10),
    );
  }

  Widget _tierBadge(String tier) {
    final isHigh = tier.toUpperCase() == 'HIGH';

    return _badge(
      label: isHigh ? 'High' : 'Medium',
      foreground:
          isHigh ? Colors.red.shade700 : adminBlue,
      background: isHigh
          ? Colors.red.withValues(alpha: 0.08)
          : adminBlue.withValues(alpha: 0.08),
    );
  }

  Widget _custodyBadge(Map<String, dynamic> item) {
    if (item['itemType'] != 'FOUND') {
      return _badge(
        label: 'Not Applicable',
        foreground: AppColors.textSecondary,
        background: background,
      );
    }

    switch (item['custodyStatus']) {
      case 'RECEIVED':
        return _badge(
          label: 'Received',
          foreground: AppColors.success,
          background: AppColors.success.withValues(alpha: 0.09),
        );

      case 'NOT_DELIVERED':
        return _badge(
          label: 'Not Delivered',
          foreground: Colors.red.shade700,
          background: Colors.red.withValues(alpha: 0.08),
        );

      default:
        return _badge(
          label: 'Awaiting Receipt',
          foreground: Colors.orange.shade800,
          background: Colors.orange.withValues(alpha: 0.10),
        );
    }
  }

  Widget _custodyCell(Map<String, dynamic> item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: _custodyBadge(item),
        ),
        if (item['storageLocation'] != null) ...[
          const SizedBox(height: 5),
          Text(
            item['storageLocation'].toString(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _statusBadge(String status) {
    final color = _getStatusColor(status);

    return _badge(
      label: _formatStatus(status),
      foreground: color,
      background: color.withValues(alpha: 0.09),
    );
  }

  Widget _badge({
    required String label,
    required Color foreground,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ============================================================
  // ITEM DETAILS
  // ============================================================

  void _showItemDetails(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 650,
              maxHeight: 760,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailHeader(
                  dialogContext,
                  item,
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _detailSectionTitle(
                          'ITEM INFORMATION',
                        ),
                        const SizedBox(height: 12),

                        _detailRow(
                          'Item ID',
                          '#${item['itemId']}',
                        ),

                        _detailRow(
                          'Type',
                          _formatStatus(
                            item['itemType'].toString(),
                          ),
                        ),

                        if (item['categoryName'] != null)
                          _detailRow(
                            'Category',
                            item['categoryName'],
                          ),

                        _detailRow(
                          'Model / Approx. Model',
                          item['modelInfo'] ?? 'Not Sure',
                        ),

                        _detailRow(
                          'Colour',
                          item['colour'] ?? '—',
                        ),

                        _detailRow(
                          'Reported Location',
                          item['location'],
                        ),

                        _detailRow(
                          'Reported By',
                          item['reporterName'],
                        ),

                        _detailRow(
                          'Event Date',
                          _formatDate(
                            item['eventDate'],
                          ),
                        ),

                        _detailRow(
                          'Reported At',
                          _formatDateTime(
                            item['reportedAt'],
                          ),
                        ),

                        if (item['description'] != null) ...[
                          const SizedBox(height: 10),
                          _descriptionBox(
                            item['description'].toString(),
                          ),
                        ],

                        const SizedBox(height: 26),

                        // ==================================================
                        // READ-ONLY AUTOMATIC CLASSIFICATION
                        // ==================================================

                        _detailSectionTitle(
                          'CLASSIFICATION',
                        ),

                        const SizedBox(height: 12),

                        _detailRowWidget(
                          'Value Tier',
                          _tierBadge(
                            item['tier'].toString(),
                          ),
                        ),

                        _detailRowWidget(
                          'Classification',
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome_outlined,
                                size: 18,
                                color: adminBlue,
                              ),
                              SizedBox(width: 7),
                              Text(
                                'Automatically Classified',
                                style: TextStyle(
                                  color: textDark,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),

                        _detailRowWidget(
                          'Item Status',
                          _statusBadge(
                            item['rawStatus'].toString(),
                          ),
                        ),

                        const SizedBox(height: 26),

                        _detailSectionTitle(
                          'OFFICE CUSTODY',
                        ),

                        const SizedBox(height: 12),

                        _detailRowWidget(
                          'Custody Status',
                          _custodyBadge(item),
                        ),

                        _detailRow(
                          'Storage Location',
                          item['storageLocation'] ?? '—',
                        ),

                        if (_canConfirmReceipt(item)) ...[
                          const SizedBox(height: 22),

                          _receiptNotice(),

                          const SizedBox(height: 16),

                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(dialogContext);

                                _showConfirmReceiptDialog(
                                  item,
                                );
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: adminBlue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                              ),
                              icon: const Icon(
                                Icons.move_to_inbox_outlined,
                                size: 20,
                              ),
                              label: const Text(
                                'Confirm Item Received',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailHeader(
    BuildContext dialogContext,
    Map<String, dynamic> item,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        22,
        19,
        14,
        19,
      ),
      decoration: const BoxDecoration(
        color: AppColors.adminSoft,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              _getItemIcon(
                item['itemName'].toString(),
              ),
              color: adminBlue,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['itemName'].toString(),
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Item #${item['itemId']}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            icon: const Icon(
              Icons.close_rounded,
              size: 23,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _detailRow(
    String label,
    dynamic value,
  ) {
    return _detailRowWidget(
      label,
      Text(
        value?.toString() ?? '—',
        textAlign: TextAlign.right,
        style: const TextStyle(
          color: textDark,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _detailRowWidget(
    String label,
    Widget value,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 11,
      ),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.border,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 165,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: value,
            ),
          ),
        ],
      ),
    );
  }

  Widget _descriptionBox(String description) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        description,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _receiptNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: adminBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: adminBlue,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Confirm receipt only after the physical item has been '
              'delivered to the Lost & Found Office. The retention '
              'period will start automatically.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _canConfirmReceipt(Map<String, dynamic> item) {
    return item['itemType'] == 'FOUND' &&
        item['custodyStatus'] == 'NOT_RECEIVED';
  }

  // ============================================================
  // CONFIRM RECEIPT DIALOG
  // ============================================================

  void _showConfirmReceiptDialog(
    Map<String, dynamic> item,
  ) {
    final controller = TextEditingController();
    bool submitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: const Text(
                'Confirm Item Receipt',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['itemName'].toString(),
                      style: const TextStyle(
                        color: textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Item #${item['itemId']}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Storage Location *',
                      style: TextStyle(
                        color: textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      enabled: !submitting,
                      autofocus: true,
                      style: const TextStyle(
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g. Cabinet A-01',
                        hintStyle: const TextStyle(
                          fontSize: 14,
                        ),
                        filled: true,
                        fillColor: background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: AppColors.border,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _receiptNotice(),
                    if (submitting) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(
                        color: adminBlue,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () {
                          Navigator.pop(dialogContext);
                        },
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 14,
                    ),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: adminBlue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: submitting
                      ? null
                      : () async {
                          final storage =
                              controller.text.trim();

                          if (storage.isEmpty) {
                            _showMessage(
                              'Please enter a storage location.',
                              isError: true,
                            );
                            return;
                          }

                          setDialogState(() {
                            submitting = true;
                          });

                          final success =
                              await _confirmItemReceived(
                            itemId:
                                item['itemId'].toString(),
                            storageLocation: storage,
                          );

                          if (!mounted) return;

                          if (success) {
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }

                            _showMessage(
                              'Item received successfully. '
                              'Retention period started automatically.',
                            );
                          } else if (dialogContext.mounted) {
                            setDialogState(() {
                              submitting = false;
                            });
                          }
                        },
                  child: const Text(
                    'Confirm Receipt',
                    style: TextStyle(
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      controller.dispose();
    });
  }

  // ============================================================
  // ERROR / EMPTY STATES
  // ============================================================

  Widget _errorState() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 430,
        ),
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.border,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: Colors.red.shade700,
            ),
            const SizedBox(height: 13),
            const Text(
              'Unable to Load Items',
              style: TextStyle(
                color: textDark,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _loadItems,
              style: FilledButton.styleFrom(
                backgroundColor: adminBlue,
              ),
              icon: const Icon(
                Icons.refresh_rounded,
              ),
              label: const Text(
                'Try Again',
                style: TextStyle(
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 50,
            color: AppColors.textSecondary,
          ),
          SizedBox(height: 13),
          Text(
            'No Items Found',
            style: TextStyle(
              color: textDark,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'No database items match the current search or filter.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontSize: 14,
          ),
        ),
        backgroundColor:
            isError ? Colors.red.shade700 : adminDark,
      ),
    );
  }

  static String _extractMessage(
    http.Response response, {
    required String fallback,
  }) {
    try {
      final body = jsonDecode(response.body);

      if (body is Map<String, dynamic> &&
          body['message'] != null) {
        return body['message'].toString();
      }
    } catch (_) {}

    return fallback;
  }

  static String? _nullableText(dynamic value) {
    if (value == null) return null;

    final text = value.toString().trim();

    if (text.isEmpty) return null;

    return text;
  }

  static String _formatStatus(String status) {
    return status
        .replaceAll('_', ' ')
        .toLowerCase()
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;

          return '${word[0].toUpperCase()}${word.substring(1)}';
        })
        .join(' ');
  }

  static String _formatDate(dynamic value) {
    if (value == null) return '—';

    final parsed =
        DateTime.tryParse(value.toString());

    if (parsed == null) {
      return value.toString();
    }

    return '${parsed.day.toString().padLeft(2, '0')}/'
        '${parsed.month.toString().padLeft(2, '0')}/'
        '${parsed.year}';
  }

  static String _formatDateTime(dynamic value) {
    if (value == null) return '—';

    final parsed =
        DateTime.tryParse(value.toString());

    if (parsed == null) {
      return value.toString();
    }

    return '${parsed.day.toString().padLeft(2, '0')}/'
        '${parsed.month.toString().padLeft(2, '0')}/'
        '${parsed.year} '
        '${parsed.hour.toString().padLeft(2, '0')}:'
        '${parsed.minute.toString().padLeft(2, '0')}';
  }

  static Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'ACTIVE':
      case 'IN_STORAGE':
        return AppColors.success;

      case 'PENDING_CLAIM':
      case 'CLAIM_PENDING':
      case 'VERIFICATION_REQUIRED':
        return Colors.orange.shade800;

      case 'CLAIMED':
      case 'COLLECTED':
      case 'RETURNED':
        return adminBlue;

      case 'EXPIRED':
      case 'DISPOSED':
        return Colors.red.shade700;

      default:
        return AppColors.textSecondary;
    }
  }

  static IconData _getItemIcon(String itemName) {
    final name = itemName.toLowerCase();

    if (name.contains('laptop') ||
        name.contains('macbook')) {
      return Icons.laptop_mac_rounded;
    }

    if (name.contains('phone') ||
        name.contains('iphone') ||
        name.contains('mobile')) {
      return Icons.smartphone_rounded;
    }

    if (name.contains('wallet')) {
      return Icons.account_balance_wallet_rounded;
    }

    if (name.contains('earbud') ||
        name.contains('headphone') ||
        name.contains('airpod')) {
      return Icons.headphones_rounded;
    }

    if (name.contains('bottle')) {
      return Icons.water_drop_outlined;
    }

    if (name.contains('key')) {
      return Icons.key_rounded;
    }

    if (name.contains('watch')) {
      return Icons.watch_rounded;
    }

    if (name.contains('camera')) {
      return Icons.camera_alt_outlined;
    }

    if (name.contains('book')) {
      return Icons.menu_book_rounded;
    }

    if (name.contains('bag') ||
        name.contains('backpack')) {
      return Icons.backpack_rounded;
    }

    if (name.contains('umbrella')) {
      return Icons.umbrella_rounded;
    }

    return Icons.inventory_2_outlined;
  }
}

// ============================================================
// TABLE HEADER
// ============================================================

class _TableLabel extends StatelessWidget {
  final String text;

  const _TableLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    );
  }
}