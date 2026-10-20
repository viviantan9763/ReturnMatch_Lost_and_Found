import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../widgets/student/student_shell.dart';

class MyClaimsScreen extends StatefulWidget {
  const MyClaimsScreen({super.key});

  @override
  State<MyClaimsScreen> createState() =>
      _MyClaimsScreenState();
}

class _MyClaimsScreenState
    extends State<MyClaimsScreen> {
  static const Color studentOrange =
      AppColors.studentPrimary;

  static const Color background =
      AppColors.background;

  static const Color textDark =
      AppColors.textPrimary;

  bool _isLoading = true;
  String? _errorMessage;

  final List<Map<String, dynamic>> _claims = [];

  @override
  void initState() {
    super.initState();
    _loadClaims();
  }

  // =========================================================
  // LOAD CLAIMS
  // =========================================================

  Future<void> _loadClaims() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse(
          '${AuthService.baseUrl}/claims/my',
        ),
        headers: AuthService.authenticatedHeaders(),
      );

      final body = jsonDecode(
        response.body,
      );

      if (response.statusCode != 200) {
        throw Exception(
          body['message'] ?? 'Failed to load claims',
        );
      }

      final rawClaims =
          body['claims'] as List<dynamic>? ?? [];

      if (!mounted) return;

      setState(() {
        _claims
          ..clear()
          ..addAll(
            rawClaims.map(
              (claim) =>
                  Map<String, dynamic>.from(
                claim,
              ),
            ),
          );

        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = error
            .toString()
            .replaceFirst(
              'Exception: ',
              '',
            );
      });
    }
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return StudentShell(
      selectedPage: StudentPage.claims,
      title: 'My Claims',
      child: Container(
        color: background,
        child: Column(
          children: [
            _pageToolbar(),

            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // TOOLBAR
  // =========================================================

  Widget _pageToolbar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: AppColors.border,
          ),
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Track your submitted claim requests and verification status.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),

          IconButton(
            tooltip: 'Refresh',
            onPressed:
                _isLoading ? null : _loadClaims,
            icon: const Icon(
              Icons.refresh_rounded,
              color: studentOrange,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // BODY
  // =========================================================

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: studentOrange,
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Colors.red,
              ),

              const SizedBox(height: 12),

              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              ElevatedButton.icon(
                onPressed: _loadClaims,
                icon: const Icon(
                  Icons.refresh_rounded,
                ),
                label: const Text(
                  'Try Again',
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_claims.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 52,
                color: AppColors.textSecondary,
              ),

              SizedBox(height: 12),

              Text(
                'No Claims Yet',
                style: TextStyle(
                  color: textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),

              SizedBox(height: 6),

              Text(
                'Your submitted claims will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadClaims,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 1000,
          ),
          child: ListView.builder(
            padding: const EdgeInsets.all(18),
            itemCount: _claims.length,
            itemBuilder: (
              context,
              index,
            ) {
              return _claimCard(
                _claims[index],
              );
            },
          ),
        ),
      ),
    );
  }

  // =========================================================
  // CLAIM CARD
  // =========================================================

  Widget _claimCard(
    Map<String, dynamic> claim,
  ) {
    final claimId =
        claim['claim_id']?.toString() ?? '-';

    final itemName =
        claim['item_name']?.toString() ??
            'Unknown Item';

    final tier =
        claim['value_tier']
                ?.toString()
                .toUpperCase() ??
            'MEDIUM';

    final status =
        claim['claim_status']
                ?.toString()
                .toUpperCase() ??
            'PENDING';

    final location =
        claim['location']?.toString() ??
            'Location not provided';

    final submittedAt =
        claim['submitted_at']?.toString();

    return Container(
      margin: const EdgeInsets.only(
        bottom: 14,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.studentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _itemIcon(itemName),
                  color: studentOrange,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemName,
                      style: const TextStyle(
                        color: textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      'Claim ID: $claimId',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              _statusChip(status),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 15,
                color: AppColors.textSecondary,
              ),

              const SizedBox(width: 4),

              Expanded(
                child: Text(
                  location,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _infoChip(
                tier == 'HIGH'
                    ? 'HIGH VALUE'
                    : 'MEDIUM VALUE',
                tier == 'HIGH'
                    ? Colors.red
                    : studentOrange,
              ),

              if (submittedAt != null)
                _infoChip(
                  'Submitted',
                  AppColors.textSecondary,
                ),
            ],
          ),

          const SizedBox(height: 12),

           _statusMessage(status),

           if (status == 'PENDING') ...[
             const SizedBox(height: 12),
             SizedBox(
               width: double.infinity,
               child: ElevatedButton.icon(
                 onPressed: () => _openSecurityQuestions(claimId),
                 icon: const Icon(Icons.security_rounded, size: 18),
                 label: const Text('Answer Security Questions'),
                 style: ElevatedButton.styleFrom(
                   backgroundColor: studentOrange,
                   foregroundColor: Colors.white,
                   padding: const EdgeInsets.symmetric(vertical: 12),
                 ),
               ),
             ),
           ],
           if (status == 'APPROVED') ...[
             const SizedBox(height: 12),
             SizedBox(
               width: double.infinity,
               child: OutlinedButton.icon(
                 onPressed: () => _openCollectionOtp(claimId),
                 icon: const Icon(Icons.pin_outlined, size: 18),
                 label: const Text('View Collection OTP'),
               ),
             ),
           ],
        ],
      ),
    );
  }

  // =========================================================
  // CLAIM SECURITY QUESTIONS
  // =========================================================
  Future<void> _openSecurityQuestions(String claimId) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _SecurityQuestionsDialog(
        claimId: claimId,
        onCompleted: _loadClaims,
      ),
    );
  }

  Future<void> _openCollectionOtp(String claimId) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _CollectionOtpDialog(claimId: claimId),
    );
  }

  // =========================================================
  // STATUS CHIP
  // =========================================================

  Widget _statusChip(
    String status,
  ) {
    Color color;

    switch (status) {
      case 'APPROVED':
        color = AppColors.success;
        break;

      case 'REJECTED':
        color = Colors.red;
        break;

      case 'VERIFICATION_REQUIRED':
        color = Colors.orange;
        break;

      case 'COLLECTED':
        color = studentOrange;
        break;

      default:
        color = AppColors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.10,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _formatStatus(status),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // =========================================================
  // INFO CHIP
  // =========================================================

  Widget _infoChip(
    String text,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.08,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // =========================================================
  // STATUS MESSAGE
  // =========================================================

  Widget _statusMessage(
    String status,
  ) {
    String message;

    switch (status) {
      case 'PENDING':
        message = 'Please answer the two private security questions to continue your claim.';
        break;
      case 'VERIFICATION_REQUIRED':
        message =
            'Your security answers are waiting for administrator verification.';
        break;

      case 'APPROVED':
        message =
            'Your claim has been approved. Staff will generate a 10-minute OTP when you arrive for collection.';
        break;

      case 'REJECTED':
        message =
            'Your claim was rejected after verification.';
        break;

      case 'COLLECTED':
        message =
            'Item collection has been completed.';
        break;

      default:
        message =
            'Your claim is currently being processed.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          height: 1.4,
        ),
      ),
    );
  }

  // =========================================================
  // FORMAT STATUS
  // =========================================================

  String _formatStatus(
    String status,
  ) {
    return status
        .replaceAll('_', ' ')
        .toLowerCase()
        .split(' ')
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  // =========================================================
  // ITEM ICON
  // =========================================================

  IconData _itemIcon(
    String name,
  ) {
    final lower = name.toLowerCase();

    if (lower.contains('phone') ||
        lower.contains('iphone')) {
      return Icons.smartphone_rounded;
    }

    if (lower.contains('laptop')) {
      return Icons.laptop_mac_rounded;
    }

    if (lower.contains('wallet')) {
      return Icons.account_balance_wallet_rounded;
    }

    if (lower.contains('bag')) {
      return Icons.backpack_rounded;
    }

    return Icons.inventory_2_rounded;
  }
}


// Dialog reads only trusted question text; reference answers stay on server.
class _SecurityQuestionsDialog extends StatefulWidget {
  final String claimId;
  final Future<void> Function() onCompleted;
  const _SecurityQuestionsDialog({required this.claimId, required this.onCompleted});

  @override
  State<_SecurityQuestionsDialog> createState() => _SecurityQuestionsDialogState();
}

class _SecurityQuestionsDialogState extends State<_SecurityQuestionsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _answerOne = TextEditingController();
  final _answerTwo = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  String? _error;
  List<Map<String, dynamic>> _questions = [];

  @override
  void initState() {
    super.initState();
    _fetchQuestions();
  }

  @override
  void dispose() {
    _answerOne.dispose();
    _answerTwo.dispose();
    super.dispose();
  }

  Future<void> _fetchQuestions() async {
    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/claims/${widget.claimId}/security-questions'),
        headers: AuthService.authenticatedHeaders(),
      );
      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200) {
        throw Exception(decoded['message'] ?? 'Could not load questions');
      }
      final raw = decoded['questions'] as List<dynamic>? ?? [];
      final questions = raw.map((q) => Map<String, dynamic>.from(q as Map)).toList();
      questions.sort((a, b) => (int.tryParse('${a['question_no']}') ?? 0)
          .compareTo(int.tryParse('${b['question_no']}') ?? 0));
      if (questions.length != 2 ||
          questions[0]['question_no'].toString() != '1' ||
          questions[1]['question_no'].toString() != '2') {
        throw Exception('This found item does not have two security questions. Contact admin.');
      }
      if (decoded['claim_status']?.toString().toUpperCase() != 'PENDING') {
        throw Exception('This claim is no longer waiting for answers. Refresh My Claims.');
      }
      if (!mounted) return;
      setState(() { _questions = questions; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_sending || !_formKey.currentState!.validate()) return;
    setState(() { _sending = true; _error = null; });
    try {
      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/claims/${widget.claimId}/security-answers'),
        headers: {
          ...AuthService.authenticatedHeaders(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'answers': [
            {'question_no': 1, 'answer_text': _answerOne.text.trim()},
            {'question_no': 2, 'answer_text': _answerTwo.text.trim()},
          ],
        }),
      );
      final decoded = jsonDecode(response.body);
      if (response.statusCode != 201) {
        throw Exception(decoded['message'] ?? 'Unable to submit answers');
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onCompleted();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(decoded['message']?.toString() ?? 'Answers submitted'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Verify Ownership'),
      content: SizedBox(
        width: 480,
        child: _loading
            ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Answer both private questions. Answers are checked against information provided by the finder.'),
                      const SizedBox(height: 16),
                      if (_questions.length == 2) ...[
                        Text('1. ${_questions[0]['question_text']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _answerOne,
                          maxLength: 250,
                          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Answer 1'),
                          validator: (v) => v == null || v.trim().length < 2 ? 'Please enter your answer' : null,
                        ),
                        const SizedBox(height: 12),
                        Text('2. ${_questions[1]['question_text']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _answerTwo,
                          maxLength: 250,
                          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Answer 2'),
                          validator: (v) => v == null || v.trim().length < 2 ? 'Please enter your answer' : null,
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!, style: const TextStyle(color: Colors.red)),
                      ],
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_questions.length == 2)
          FilledButton(
            onPressed: _sending ? null : _submit,
            child: Text(_sending ? 'Submitting...' : 'Submit Answers'),
          ),
      ],
    );
  }
}

class _CollectionOtpDialog extends StatefulWidget {
  final String claimId;
  const _CollectionOtpDialog({required this.claimId});
  @override
  State<_CollectionOtpDialog> createState() => _CollectionOtpDialogState();
}

class _CollectionOtpDialogState extends State<_CollectionOtpDialog> {
  bool _loading = true;
  String? _otp;
  String? _message;
  String? _expires;

  @override
  void initState() { super.initState(); _fetch(); }

  Future<void> _fetch() async {
    setState(() { _loading = true; _message = null; _otp = null; });
    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/claims/${widget.claimId}/otp'),
        headers: AuthService.authenticatedHeaders(),
      );
      final decoded = jsonDecode(response.body);
      if (!mounted) return;
      setState(() {
        if (response.statusCode == 200) {
          final data = decoded['otp'] as Map<String, dynamic>;
          _otp = data['otp_code']?.toString();
          _expires = data['expired_at']?.toString();
        } else {
          _message = decoded['message']?.toString() ?? 'No active OTP';
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _message = 'Unable to load OTP: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Collection OTP'),
    content: SizedBox(
      width: 350,
      child: _loading
          ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_otp != null) ...[
                  SelectableText(_otp!, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 5)),
                  const SizedBox(height: 12),
                  Text('Expires: ${_expires ?? '10 minutes after generation'}'),
                ] else ...[
                  const Icon(Icons.info_outline, size: 40),
                  const SizedBox(height: 12),
                  Text(_message ?? 'Please ask staff to generate an OTP when you arrive.', textAlign: TextAlign.center),
                ],
              ],
            ),
    ),
    actions: [
      TextButton(onPressed: _loading ? null : _fetch, child: const Text('Refresh')),
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
    ],
  );
}
