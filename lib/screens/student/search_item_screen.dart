import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../widgets/student/student_shell.dart';

/// Phase 1: live keyword search + public FOUND listings + claim submission.
/// Image search / AI ranking require a dedicated server endpoint and are NOT simulated.
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

  Future<void> _loadItems() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/items'),
        headers: AuthService.authenticatedHeaders(),
      );
      if (response.statusCode != 200) {
        throw Exception(_message(response, 'Unable to load items'));
      }
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || body['items'] is! List) {
        throw Exception('Unexpected item response from server');
      }
      final list = (body['items'] as List)
          .whereType<Map<String, dynamic>>()
          // Never show unpublished or unavailable reports in public search.
          // The server also enforces publication permissions.
          .where((i) => _upper(i['publication_status']) == 'PUBLISHED')
          .where((i) => _upper(i['item_type']) == 'FOUND')
          .where((i) => const ['ACTIVE', 'MATCHED', 'CLAIM_PENDING']
              .contains(_upper(i['status'])))
          .toList();
      if (!mounted) return;
      setState(() { _items = list; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  String _upper(Object? value) => (value ?? '').toString().toUpperCase();
  String _string(Object? value) => (value ?? '').toString();

  String _message(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['message'] != null) return body['message'].toString();
    } catch (_) {}
    return '$fallback (HTTP ${response.statusCode})';
  }

  List<Map<String, dynamic>> get _visibleItems {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((item) {
      final text = [
        item['item_name'], item['category_name'], item['description'],
        item['model_info'], item['colour'], item['location'],
      ].map(_string).join(' ').toLowerCase();
      return text.contains(q);
    }).toList();
  }

  Future<void> _claimItem(Map<String, dynamic> item) async {
    final id = item['item_id'];
    if (id == null) return;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Claim found item'),
        content: Column(
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
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
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
      );
      if (response.statusCode != 201) {
        throw Exception(_message(response, 'Claim could not be submitted'));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Claim submitted. Track its status in My Claims.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

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
              Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _search,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, color: orange),
                        hintText: 'Search found items by keyword',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        suffixIcon: IconButton(
                          tooltip: 'Refresh',
                          onPressed: _loadItems,
                          icon: const Icon(Icons.refresh),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(children: [
                              Icon(Icons.image_search_outlined, color: orange),
                              SizedBox(width: 10),
                              Text('Image Search', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                            ]),
                            const SizedBox(height: 8),
                            const Text('Image-based search will be available after the AI search endpoint is connected.'),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: null,
                              icon: Icon(Icons.upload_outlined),
                              label: Text('Upload Image (not connected)'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(children: [
                      const Expanded(child: Text('Found Items', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
                      if (!_loading) Text('${results.length} results'),
                    ]),
                    const SizedBox(height: 12),
                    if (_loading) const Center(child: Padding(
                      padding: EdgeInsets.all(36), child: CircularProgressIndicator(),
                    )) else if (_error != null) Card(child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(children: [
                        Text(_error!, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 10),
                        TextButton(onPressed: _loadItems, child: const Text('Retry')),
                      ]),
                    )) else if (results.isEmpty) Card(child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Center(child: Text(_query.trim().isEmpty
                        ? 'No published, available found items yet.'
                        : 'No published found items match "${_query.trim()}".')),
                    )) else ...results.map((item) => Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.inventory_2_outlined, color: orange),
                              const SizedBox(width: 10),
                              Expanded(child: Text(_string(item['item_name']),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                              Chip(label: Text(_string(item['value_tier']).toUpperCase())),
                            ]),
                            const SizedBox(height: 8),
                            Text('Category: ${_string(item['category_name'])}'),
                            if (_string(item['location']).isNotEmpty)
                              Text('Location: ${_string(item['location'])}'),
                            if (_string(item['description']).isNotEmpty)
                              Text('Description: ${_string(item['description'])}'),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: _claiming ? null : () => _claimItem(item),
                                icon: const Icon(Icons.verified_user_outlined),
                                label: const Text('Claim Item'),
                                style: FilledButton.styleFrom(backgroundColor: orange),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
                    const SizedBox(height: 24),
                    const Text('AI Match Results', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('AI ranking will be connected after the matching generation and publication-safety checks are verified.'),
                  ],
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }
}
