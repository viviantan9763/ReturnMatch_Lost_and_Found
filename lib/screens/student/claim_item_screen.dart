import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';
import 'my_claims_screen.dart';

class ClaimItemScreen extends StatefulWidget {
  final int itemId;
  final String itemName;
  final String valueTier;

  const ClaimItemScreen({
    super.key,
    required this.itemId,
    required this.itemName,
    required this.valueTier,
  });

  @override
  State<ClaimItemScreen> createState() =>
      _ClaimItemScreenState();
}

class _ClaimItemScreenState extends State<ClaimItemScreen> {
  static const Color studentOrange = AppColors.studentPrimary;
  static const Color background = AppColors.background;
  static const Color textDark = AppColors.textPrimary;

  final _formKey = GlobalKey<FormState>();

  final TextEditingController _claimReasonController =
      TextEditingController();

  bool _isSubmitting = false;
  int? _createdClaimId;
  bool _creationUncertain = false;
  final String? _claimantId = AuthService.currentUser?['user_id']?.toString();

  bool get _isCurrentUser =>
      _claimantId != null &&
      AuthService.currentUser?['user_id']?.toString() == _claimantId &&
      AuthService.authToken?.isNotEmpty == true;

  @override
  void dispose() {
    _claimReasonController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw Exception('Unexpected server response (HTTP ${response.statusCode}).');
  }

  Future<int?> _findExistingClaim() async {
    if (!_isCurrentUser) throw Exception('Please reopen this page after signing in.');
    final response = await http.get(
      Uri.parse('${AuthService.baseUrl}/claims/my'),
      headers: AuthService.authenticatedHeaders(),
    ).timeout(const Duration(seconds: 20));
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw Exception(body['message'] ?? 'Could not check your existing claims.');
    }
    if (!_isCurrentUser) throw Exception('Your session changed. Reopen My Claims.');
    final claims = body['claims'];
    if (claims is! List || claims.any((claim) => claim is! Map)) {
      throw Exception('Invalid claim history. Please refresh My Claims.');
    }
    for (final claim in claims.cast<Map>()) {
      final id = int.tryParse('${claim['claim_id']}');
      final itemId = int.tryParse('${claim['item_id']}');
      if (id == null || id < 1 || itemId == null || itemId < 1 ||
          claim['claim_status'] is! String ||
          (claim['claim_status'] as String).trim().isEmpty) {
        throw Exception('Invalid claim history. Please refresh My Claims.');
      }
      if (itemId == widget.itemId &&
          const ['PENDING', 'UNDER_REVIEW', 'VERIFICATION_REQUIRED', 'APPROVED']
              .contains('${claim['claim_status']}'.toUpperCase())) {
        return id;
      }
    }
    return null;
  }

  void _openMyClaims([int? claimId]) {
    if (!mounted || !_isCurrentUser) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => MyClaimsScreen(initialClaimId: claimId),
      ),
    );
  }

  Future<void> _submitClaim() async {
    if (_isSubmitting) return;
    if (!_isCurrentUser) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in and reopen this page.')),
      );
      return;
    }
    if (_createdClaimId != null) {
      _openMyClaims(_createdClaimId);
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      // Re-entering this screen resumes an existing claim instead of recreating it.
      final existingId = await _findExistingClaim();
      if (!mounted) return;
      if (existingId != null) {
        _createdClaimId = existingId;
        _openMyClaims(existingId);
        return;
      }
      if (_creationUncertain) {
        throw Exception('Creation could not be confirmed yet. Refresh My Claims '
            'before attempting a new claim.');
      }
      if (!_formKey.currentState!.validate()) return;
      if (!_isCurrentUser) throw Exception('Your session changed. Reopen My Claims.');
      // A timeout or malformed success response must never trigger a blind replay.
      _creationUncertain = true;
      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/claims'),
        headers: AuthService.authenticatedHeaders(),
        body: jsonEncode({
          'item_id': widget.itemId,
          'claim_reason': _claimReasonController.text.trim(),
        }),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode >= 400 && response.statusCode < 500) {
        _creationUncertain = false;
      }
      final body = _decode(response);
      if (response.statusCode != 201) {
        if (response.statusCode == 409) {
          final savedId = await _findExistingClaim();
          if (savedId != null) {
            _createdClaimId = savedId;
            _openMyClaims(savedId);
            return;
          }
        }
        throw Exception(body['message'] ?? 'Failed to submit claim.');
      }
      final claim = body['claim'];
      final id = claim is Map ? int.tryParse('${claim['claim_id']}') : null;
      if (id == null || id < 1) {
        throw Exception('Claim may have been saved. Open My Claims to continue.');
      }
      if (!_isCurrentUser) throw Exception('Your session changed. Reopen My Claims.');
      _createdClaimId = id;
      _creationUncertain = false;
      _openMyClaims(id);
    } catch (error) {
      // Creation may have committed even when the HTTP response was lost.
      if (_creationUncertain && mounted && _isCurrentUser) {
        try {
          final savedId = await _findExistingClaim();
          if (savedId != null) {
            _createdClaimId = savedId;
            _openMyClaims(savedId);
            return;
          }
        } catch (_) {
          // Keep recovery available, without sending another creation request.
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', '')),
      ));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,

      appBar: AppBar(
        backgroundColor:
            AppColors.studentPrimary,
        foregroundColor: Colors.white,
        elevation: 0,

        title: const Text(
          'Claim Item',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),

      body: _buildClaimForm(),
    );
  }

  // -------------------------------------------------------
  // CLAIM FORM
  // -------------------------------------------------------

  Widget _buildClaimForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),

      child: Form(
        key: _formKey,

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [
            _itemSummaryCard(),

            const SizedBox(height: 22),

            const Text(
              'Claim Reason',
              style: TextStyle(
                color: textDark,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Explain why you believe this item belongs to you.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),

            const SizedBox(height: 12),

            TextFormField(
              controller:
                  _claimReasonController,
              maxLines: 4,

              decoration:
                  _inputDecoration(
                'Example: I lost this phone yesterday near the library.',
              ),

              validator: (value) {
                if (value == null ||
                    value.trim().isEmpty) {
                  return 'Claim reason is required';
                }

                return null;
              },
            ),

            const SizedBox(height: 24),

            const Text(
              'Security Verification',
              style: TextStyle(
                color: textDark,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              widget.valueTier
                          .toUpperCase() ==
                      'HIGH'
                  ? 'This is a High Value item. Please provide detailed ownership information for administrator verification.'
                  : 'Provide ownership information to support your claim.',

              style: const TextStyle(
                color:
                    AppColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),

            const SizedBox(height: 18),

            _verificationInfoCard(),
            if (_creationUncertain)
              TextButton(
                onPressed: _isSubmitting ? null : () => _openMyClaims(),
                child: const Text('Open My Claims'),
              ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,

              child: ElevatedButton.icon(
                onPressed:
                    _isSubmitting
                        ? null
                        : _submitClaim,

                style:
                    ElevatedButton.styleFrom(
                  backgroundColor:
                      studentOrange,

                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 16,
                  ),

                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      12,
                    ),
                  ),
                ),

                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,

                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                          color:
                              Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons
                            .verified_user_outlined,
                        color:
                            Colors.white,
                      ),

                label: Text(
                  _isSubmitting
                      ? 'Submitting...'
                      : _creationUncertain
                          ? 'Check Existing Claim'
                          : 'Submit Claim',

                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------
  // ITEM SUMMARY
  // -------------------------------------------------------

  Widget _itemSummaryCard() {
    final bool high =
        widget.valueTier
                .toUpperCase() ==
            'HIGH';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppColors.studentPrimary,
            AppColors.studentDark,
          ],
        ),

        borderRadius:
            BorderRadius.circular(16),
      ),

      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,

            decoration: BoxDecoration(
              color: Colors.white
                  .withValues(
                alpha: 0.16,
              ),

              borderRadius:
                  BorderRadius.circular(
                16,
              ),
            ),

            child: Icon(
              _itemIcon(
                widget.itemName,
              ),
              size: 32,
              color: Colors.white,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [
                Text(
                  widget.itemName,

                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  'Item ID: ${widget.itemId}',

                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),

                const SizedBox(height: 7),

                Container(
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),

                  decoration: BoxDecoration(
                    color: Colors.white
                        .withValues(
                      alpha: 0.16,
                    ),

                    borderRadius:
                        BorderRadius.circular(
                      20,
                    ),
                  ),

                  child: Text(
                    high
                        ? 'HIGH VALUE'
                        : 'MEDIUM VALUE',

                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------
  // INFORMATION CARD
  // -------------------------------------------------------

  Widget _verificationInfoCard() {
    return Container(
      padding: const EdgeInsets.all(15),

      decoration: BoxDecoration(
        color:
            const Color(0xFFFFF7ED),

        borderRadius:
            BorderRadius.circular(12),

        border: Border.all(
          color:
              const Color(0xFFFED7AA),
        ),
      ),

      child: const Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [
          Icon(
            Icons.security_outlined,
            color: Colors.orange,
          ),

          SizedBox(width: 10),

          Expanded(
            child: Text(
              'After submitting, answer the two item-specific ownership questions in My Claims. '
              'Do not include passwords, PINs or other highly sensitive information.',

              style: TextStyle(
                color: textDark,
                fontSize: 12,
                height: 1.4,
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(
    String hint,
  ) {
    return InputDecoration(
      hintText: hint,

      filled: true,

      fillColor:
          AppColors.background,

      border: OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),

      focusedBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(10),

        borderSide:
            const BorderSide(
          color:
              AppColors.studentPrimary,
        ),
      ),
    );
  }

  IconData _itemIcon(
    String itemName,
  ) {
    final value =
        itemName.toLowerCase();

    if (value.contains('phone') ||
        value.contains('iphone')) {
      return Icons.smartphone_rounded;
    }

    if (value.contains('laptop')) {
      return Icons.laptop_mac_rounded;
    }

    if (value.contains('wallet')) {
      return Icons
          .account_balance_wallet_rounded;
    }

    if (value.contains('bag')) {
      return Icons.backpack_rounded;
    }

    return Icons.inventory_2_rounded;
  }
}
