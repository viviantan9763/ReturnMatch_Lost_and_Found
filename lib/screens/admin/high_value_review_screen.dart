import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';

/// Admin-only publication review of HIGH-value LOST / FOUND reports.
/// Backend endpoints:
/// GET   /api/items/review-queue
/// PATCH /api/items/:id/publication
/// Approval/rejection is saved with an audit log and reporter notification
/// by the existing Node.js item_publication_controller.js.
class HighValueReviewScreen extends StatefulWidget {
  const HighValueReviewScreen({super.key});

  @override
  State<HighValueReviewScreen> createState() =>
      _HighValueReviewScreenState();
}

class _HighValueReviewScreenState extends State<HighValueReviewScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  int? _busyItemId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  String _message(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['message'] != null) {
        return body['message'].toString();
      }
    } catch (_) {}
    return fallback;
  }

  Future<void> _loadQueue() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/items/review-queue'),
        headers: AuthService.authenticatedHeaders(),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception(_message(
          response,
          response.statusCode == 401
              ? 'Session expired. Please log in again.'
              : response.statusCode == 403
                  ? 'Admin access required. Please log in as Admin.'
                  : 'Failed to load review queue (${response.statusCode}).',
        ));
      }

      final body = jsonDecode(response.body);
      final raw = body is Map && body['items'] is List
          ? body['items'] as List
          : <dynamic>[];
      if (!mounted) return;
      setState(() {
        _items = raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _approve(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve high-value report?'),
        content: Text(
          'Publish "${item['item_name'] ?? 'Item'}" (ID ${item['item_id']})? '
          'The reporter will receive an approval notification.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _review(item, 'APPROVED', 'Admin verified report');
    }
  }

  Future<void> _reject(Map<String, dynamic> item) async {
    String reason = '';
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject high-value report'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Item: ${item['item_name'] ?? 'Unknown'}'),
            const SizedBox(height: 12),
            TextField(
              onChanged: (value) => reason = value,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason (required)',
                hintText: 'e.g. Image is unclear; please resubmit.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final note = reason.trim();
              if (note.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Please enter a reason.')),
                );
                return;
              }
              Navigator.pop(dialogContext, note);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (note != null && note.isNotEmpty) {
      await _review(item, 'REJECTED', note);
    }
  }

  Future<void> _review(
    Map<String, dynamic> item,
    String decision,
    String note,
  ) async {
    final itemId = int.tryParse('${item['item_id']}');
    if (itemId == null || _busyItemId != null) return;
    setState(() => _busyItemId = itemId);
    try {
      final response = await http.patch(
        Uri.parse('${AuthService.baseUrl}/items/$itemId/publication'),
        headers: {
          ...AuthService.authenticatedHeaders(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'decision': decision,
          'review_note': note,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception(_message(
          response,
          'Review failed (${response.statusCode}).',
        ));
      }

      if (!mounted) return;
      setState(() => _items.removeWhere((e) => e['item_id'] == itemId));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          decision == 'APPROVED'
              ? 'Report #$itemId approved. Notification saved.'
              : 'Report #$itemId rejected. Notification saved.',
        ),
        backgroundColor: AppColors.success,
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', '')),
        backgroundColor: Colors.red.shade700,
      ));
    } finally {
      if (mounted) setState(() => _busyItemId = null);
    }
  }

  String _field(Map<String, dynamic> item, String key) {
    final value = item[key]?.toString().trim();
    return value == null || value.isEmpty ? '—' : value;
  }

  String? _imageUrl(Map<String, dynamic> item) {
    final path = item['image_path']?.toString().trim() ?? '';
    if (path.isEmpty) return null;
    final parsed = Uri.tryParse(path);
    if (parsed == null) return null;
    if (parsed.hasScheme && (parsed.scheme == 'http' || parsed.scheme == 'https')) {
      return path;
    }
    if (path.contains('\\')) return null; // local Windows path is not a URL
    final origin = Uri.parse(AuthService.baseUrl).origin;
    return '$origin/${path.replaceFirst(RegExp(r'^/+'), '')}';
  }

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text.rich(TextSpan(
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        )),
      );

  Widget _itemCard(Map<String, dynamic> item) {
    final id = int.tryParse('${item['item_id']}');
    final busy = id != null && _busyItemId == id;
    final url = _imageUrl(item);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 1,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '#${_field(item, 'item_id')}  ${_field(item, 'item_name')}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Chip(label: Text('HIGH • Pending Review')),
                Chip(label: Text(_field(item, 'item_type'))),
              ],
            ),
            const SizedBox(height: 12),
            if (url != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  height: 160,
                  width: 220,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    height: 70,
                    child: Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _detail('Category', _field(item, 'category_name')),
            _detail('Reported by', _field(item, 'reporter_name')),
            _detail('Model', _field(item, 'model_info')),
            _detail('Colour', _field(item, 'colour')),
            _detail('Location', _field(item, 'location')),
            _detail('Event date', _field(item, 'event_date')),
            _detail('Description', _field(item, 'description')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy || _busyItemId != null
                      ? null
                      : () => _approve(item),
                  icon: busy
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: const Text('Approve'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: busy || _busyItemId != null
                      ? null
                      : () => _reject(item),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('High-Value Report Review'),
        backgroundColor: AppColors.adminPrimary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busyItemId == null ? _loadQueue : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _loadQueue,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadQueue,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        'Pending HIGH Reports (${_items.length})',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Approve or reject a report before it becomes public. '
                        'Each decision creates an audit log and a notification.',
                      ),
                      const SizedBox(height: 18),
                      if (_items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: Text('No high-value reports pending review.'),
                          ),
                        )
                      else
                        ..._items.map(_itemCard),
                    ],
                  ),
                ),
    );
  }
}
