import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../services/auth_service.dart';
import '../../widgets/admin/admin_shell.dart';

/// Standalone Admin OTP counter content. Embed in your existing AdminShell,
/// or navigate to this screen from the Admin dashboard.
class OtpCollectionScreen extends StatefulWidget {
  const OtpCollectionScreen({super.key});

  @override
  State<OtpCollectionScreen> createState() => _OtpCollectionScreenState();
}

class _OtpCollectionScreenState extends State<OtpCollectionScreen> {
  final _otpController = TextEditingController();
  Map<String, dynamic>? _collection;
  bool _busy = false;
  bool _completed = false;
  String? _error;
  String? _success;
  static const _brown = Color(0xFF995000);

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  String _message(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message'].toString();
      }
    } catch (_) {}
    return 'Request failed (HTTP ${response.statusCode})';
  }

  Future<void> _lookup() async {
    final code = _otpController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Please enter a 6-digit OTP.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
      _collection = null;
      _completed = false;
    });
    try {
      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/collection/lookup'),
        headers: AuthService.authenticatedHeaders(),
        body: jsonEncode({'otp_code': code}),
      );
      if (response.statusCode != 200) throw Exception(_message(response));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['collection'] is! Map) {
        throw Exception('Unexpected server response');
      }
      if (!mounted) return;
      setState(() => _collection = Map<String, dynamic>.from(decoded['collection'] as Map));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final info = _collection;
    if (info == null || _busy) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm physical handover?'),
        content: Text('Confirm that ${info['claimant_name'] ?? 'the claimant'} has received ${info['item_name'] ?? 'the item'}? This cannot be undone from this page.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm Collection')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() { _busy = true; _error = null; _success = null; });
    try {
      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/collection/confirm'),
        headers: AuthService.authenticatedHeaders(),
        body: jsonEncode({
          'otp_code': _otpController.text.trim(),
          'claim_id': info['claim_id'],
        }),
      );
      if (response.statusCode != 200) throw Exception(_message(response));
      if (!mounted) return;
      setState(() {
        _completed = true;
        _success = 'Collection completed. Claim is COLLECTED and item is CLAIMED.';
        _otpController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String title, Object? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 140, child: Text(title, style: const TextStyle(color: Colors.black54))),
      Expanded(child: Text('${value ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w600))),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedPage: AdminPage.otpCollection,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Card(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Find Collection by OTP', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Ask the student for their 6-digit collection code.'),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _otpController,
                    maxLength: 6,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Collection OTP', hintText: 'Enter 6-digit code', border: OutlineInputBorder(), counterText: ''),
                    onChanged: (_) { if (_collection != null || _completed) setState(() { _collection = null; _completed = false; _success = null; }); },
                    onSubmitted: (_) => _lookup(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _brown, padding: const EdgeInsets.symmetric(vertical: 16)),
                    onPressed: _busy ? null : _lookup,
                    icon: const Icon(Icons.search),
                    label: Text(_busy ? 'Please wait...' : 'Look Up Claim'),
                  ),
                ]),
              )),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
              if (_success != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_success!, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
              if (_collection != null) ...[
                const SizedBox(height: 18),
                Card(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('Claim & Item Information', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 14),
                    _field('Claim ID', _collection!['claim_id']),
                    _field('Claimant', _collection!['claimant_name']),
                    _field('Email', _collection!['claimant_email']),
                    _field('Item ID', _collection!['item_id']),
                    _field('Item', _collection!['item_name']),
                    _field('Value Tier', _collection!['value_tier']),
                    _field('Location', _collection!['location']),
                    _field('Claim Status', _completed ? 'COLLECTED' : _collection!['claim_status']),
                    const SizedBox(height: 16),
                    const Text('Verify the person and physically hand over the correct item before confirming.', style: TextStyle(color: Colors.black54)),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: _brown, padding: const EdgeInsets.symmetric(vertical: 16)),
                      onPressed: _busy || _completed ? null : _confirm,
                      icon: const Icon(Icons.verified),
                      label: Text(_completed ? 'Collection Completed' : 'Confirm Collection'),
                    ),
                  ]),
                )),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
