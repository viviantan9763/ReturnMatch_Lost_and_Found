import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../widgets/student/student_shell.dart';

/// Public browse + keyword search for published Lost and Found reports.
/// Claim submission is available for FOUND items only.
/// Image search and AI ranking are not simulated here.
class SearchItemScreen extends StatefulWidget {
  const SearchItemScreen({super.key});

  @override
  State<SearchItemScreen> createState() => _SearchItemScreenState();
}

class _SearchItemScreenState extends State<SearchItemScreen> {
  static const Color orange = AppColors.studentPrimary;
  final TextEditingController _search = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _claiming = false;
  String? _error;
  String _query = '';
  String _typeFilter = 'ALL';
  String _categoryFilter = 'All categories';

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _upper(Object? value) => (value ?? '').toString().toUpperCase();
  String _string(Object? value) => (value ?? '').toString();

  String _message(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['message'] != null) {
        return body['message'].toString();
      }
    } catch (_) {}
    return '$fallback (HTTP ${response.statusCode})';
  }

  Future<void> _loadItems() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/items'),
        headers: AuthService.authenticatedHeaders(),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception(_message(response, 'Unable to load items'));
      }
      final body = jsonDecode(response.body);
      if (body is! Map || body['items'] is! List) {
        throw Exception('Unexpected item response from server');
      }
      final list = (body['items'] as List)
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          // Do not show pending, disposed or collected reports.
          .where((item) => _upper(item['publication_status']) == 'PUBLISHED')
          .where((item) => const ['LOST', 'FOUND'].contains(_upper(item['item_type'])))
          .where((item) => const ['ACTIVE', 'MATCHED', 'CLAIM_PENDING']
              .contains(_upper(item['status'])))
          .toList();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        if (_categoryFilter != 'All categories' &&
            !_categories.contains(_categoryFilter)) {
          _categoryFilter = 'All categories';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<String> get _categories {
    final categories = _items
        .map((item) => _string(item['category_name']).trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['All categories', ...categories];
  }

  List<Map<String, dynamic>> get _visibleItems {
    final query = _query.trim().toLowerCase();
    return _items.where((item) {
      if (_typeFilter != 'ALL' && _upper(item['item_type']) != _typeFilter) {
        return false;
      }
      if (_categoryFilter != 'All categories' &&
          _string(item['category_name']) != _categoryFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      final searchable = [
        item['item_name'],
        item['category_name'],
        item['description'],
        item['model_info'],
        item['colour'],
        item['location'],
      ].map(_string).join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  // Support common image fields without assuming a particular API response.
  // Relative paths are resolved against the backend origin, not the /api path.
  String? _imageUrl(Map<String, dynamic> item) {
    dynamic candidate = item['image_url'] ?? item['image_path'] ??
        item['photo_url'] ?? item['photo_path'] ?? item['image'];
    final images = item['images'];
    if ((candidate == null || candidate.toString().trim().isEmpty) &&
        images is List && images.isNotEmpty) {
      candidate = images.first;
    }
    if (candidate is Map) {
      candidate = candidate['image_url'] ?? candidate['image_path'] ??
          candidate['url'] ?? candidate['path'];
    }
    if (candidate is! String || candidate.trim().isEmpty) return null;
    final value = candidate.trim().replaceAll('\\', '/');
    if (value.startsWith('data:image/')) return value;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    if (uri.hasScheme) {
      return (uri.scheme == 'http' || uri.scheme == 'https') ? value : null;
    }
    final base = Uri.tryParse(AuthService.baseUrl);
    if (base == null || !base.hasAuthority) return null;
    final origin = Uri(scheme: base.scheme, host: base.host, port: base.hasPort ? base.port : null);
    return origin.resolve(value.startsWith('/') ? value : '/$value').toString();
  }

  Future<void> _claimItem(Map<String, dynamic> item) async {
    if (_upper(item['item_type']) != 'FOUND') return;
    final id = item['item_id'];
    if (id == null || _claiming) return;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Claim found item'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Item: ${_string(item['item_name'])}'),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Why do you believe this is yours?',
                  border: OutlineInputBorder(),
                ),
              ),
              const Text(
                'The Lost & Found administrator will review your request. '
                'Additional verification may be required.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().isEmpty) return;
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Submit claim'),
          ),
        ],
      ),
    );
    final claimReason = reason.text.trim();
    reason.dispose();
    if (confirmed != true || _claiming || !mounted) return;
    setState(() => _claiming = true);
    try {
      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/claims'),
        headers: AuthService.authenticatedHeaders(),
        body: jsonEncode({'item_id': id, 'claim_reason': claimReason}),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 201) {
        throw Exception(_message(response, 'Claim could not be submitted'));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Claim submitted. Track its status in My Claims.')),
      );
      await _loadItems();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  void _showDetails(Map<String, dynamic> item) {
    final isFound = _upper(item['item_type']) == 'FOUND';
    final image = _imageUrl(item);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_string(item['item_name']).isEmpty
            ? 'Item details'
            : _string(item['item_name'])),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (image != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      image,
                      height: 210,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _imagePlaceholder(height: 170),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _detailLine('Type', isFound ? 'Found' : 'Lost'),
                _detailLine('Category', _string(item['category_name'])),
                _detailLine('Location', _string(item['location'])),
                _detailLine('Colour', _string(item['colour'])),
                _detailLine('Description', _string(item['description'])),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          if (isFound)
            FilledButton(
              onPressed: _claiming
                  ? null
                  : () {
                      Navigator.pop(dialogContext);
                      _claimItem(item);
                    },
              style: FilledButton.styleFrom(backgroundColor: orange),
              child: const Text('Claim Item'),
            ),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('$label: $value'),
    );
  }

  Widget _imagePlaceholder({double? height}) => Container(
        height: height,
        color: const Color(0xFFFFF3E4),
        alignment: Alignment.center,
        child: const Icon(Icons.inventory_2_outlined, color: orange, size: 54),
      );

  Widget _itemCard(Map<String, dynamic> item) {
    final isFound = _upper(item['item_type']) == 'FOUND';
    final image = _imageUrl(item);
    final name = _string(item['item_name']);
    final category = _string(item['category_name']);
    final location = _string(item['location']);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () => _showDetails(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.45,
              child: image == null
                  ? _imagePlaceholder()
                  : Image.network(
                      image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _imagePlaceholder(),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isFound ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isFound ? 'FOUND' : 'LOST',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isFound ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (category.isNotEmpty)
                        Flexible(
                          child: Text(
                            category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    name.isEmpty ? 'Unnamed item' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, size: 15, color: Colors.grey.shade600),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          location.isEmpty ? 'Location not specified' : location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => _showDetails(item),
                          child: const Text('View Details'),
                        ),
                      ),
                      if (isFound) ...[
                        const SizedBox(width: 5),
                        Expanded(
                          child: FilledButton(
                            onPressed: _claiming ? null : () => _claimItem(item),
                            style: FilledButton.styleFrom(
                              backgroundColor: orange,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                            ),
                            child: const Text('Claim', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value) => ChoiceChip(
        label: Text(label),
        selected: _typeFilter == value,
        selectedColor: const Color(0xFFFFE6C5),
        onSelected: (_) => setState(() => _typeFilter = value),
      );

  @override
  Widget build(BuildContext context) {
    final results = _visibleItems;
    return StudentShell(
      selectedPage: StudentPage.search,
      title: 'Search Items',
      child: Container(
        color: AppColors.background,
        child: RefreshIndicator(
          onRefresh: _loadItems,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Explore Lost & Found',
                          style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      Text('Browse recently published items or search for something specific.',
                          style: TextStyle(color: Colors.grey.shade700)),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _search,
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search, color: orange),
                          hintText: 'Search by item name, category, colour or location',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          suffixIcon: IconButton(
                            tooltip: _query.isEmpty ? 'Refresh items' : 'Clear search',
                            onPressed: _query.isEmpty
                                ? _loadItems
                                : () {
                                    _search.clear();
                                    setState(() => _query = '');
                                  },
                            icon: Icon(_query.isEmpty ? Icons.refresh : Icons.close),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _filterChip('All', 'ALL'),
                          _filterChip('Lost', 'LOST'),
                          _filterChip('Found', 'FOUND'),
                          const SizedBox(width: 4),
                          DropdownButton<String>(
                            value: _categories.contains(_categoryFilter)
                                ? _categoryFilter
                                : 'All categories',
                            items: _categories
                                .map((category) => DropdownMenuItem(
                                      value: category,
                                      child: Text(category),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _categoryFilter = value);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Recently Reported Items',
                                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                          ),
                          if (!_loading && _error == null)
                            Text('${results.length} items',
                                style: TextStyle(color: Colors.grey.shade700)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_error != null)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                Text(_error!, style: const TextStyle(color: Colors.red)),
                                const SizedBox(height: 10),
                                TextButton(onPressed: _loadItems, child: const Text('Retry')),
                              ],
                            ),
                          ),
                        )
                      else if (results.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                              child: Text(_items.isEmpty
                                  ? 'No published items are available yet.'
                                  : 'No items match your current search and filters.'),
                            ),
                          ),
                        )
                      else
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth >= 850
                                ? 3
                                : constraints.maxWidth >= 530
                                    ? 2
                                    : 1;
                            const spacing = 14.0;
                            final cardWidth = (constraints.maxWidth -
                                    spacing * (columns - 1)) /
                                columns;
                            return Wrap(
                              spacing: spacing,
                              runSpacing: spacing,
                              children: results
                                  .map((item) => SizedBox(
                                        width: cardWidth,
                                        child: _itemCard(item),
                                      ))
                                  .toList(),
                            );
                          },
                        ),
                      const SizedBox(height: 24),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.image_search_outlined, color: orange),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Image Search',
                                        style: TextStyle(fontWeight: FontWeight.bold)),
                                    SizedBox(height: 5),
                                    Text('Image-based search will be available after '
                                        'the AI search endpoint is connected.'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
