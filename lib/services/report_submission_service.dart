import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'auth_service.dart';

// A report is created once; upload and matching failures resume its saved ID.
class ReportSubmission {
  int? itemId;
  String? _token;
  String? _savedPayload;
  bool _creationUncertain = false;
  bool _busy = false;
  Uint8List? _uploadedBytes;
  String? publicationStatus;

  Future<void> submit(
    Map<String, dynamic> payload, {
    Uint8List? imageBytes,
    String? imageName,
  }) async {
    if (_busy) return;
    final token = AuthService.authToken;
    if (token == null || token.isEmpty || (_token != null && token != _token)) {
      throw Exception(
        'Your session changed. Open My Reports to check the saved report.',
      );
    }
    final mime = imageBytes == null
        ? null
        : lookupMimeType(imageName ?? '', headerBytes: imageBytes);
    if (imageBytes != null &&
        (imageBytes.isEmpty ||
            imageBytes.length > 5 * 1024 * 1024 ||
            !['image/jpeg', 'image/png', 'image/webp'].contains(mime))) {
      throw Exception('Choose a JPEG, PNG or WEBP image no larger than 5 MB.');
    }
    if (_creationUncertain) {
      throw Exception(
        'The report creation outcome is unknown. Check My Reports before starting a new report.',
      );
    }
    final encoded = jsonEncode(payload);
    if (itemId != null && encoded != _savedPayload) {
      throw Exception(
        'Report #$itemId is already saved. Retry its upload with the original report details, or check My Reports.',
      );
    }
    _busy = true;
    _token = token;
    try {
      if (itemId == null) {
        _creationUncertain = true;
        final response = await http
            .post(
              Uri.parse('${AuthService.baseUrl}/items'),
              headers: AuthService.authenticatedHeaders(),
              body: jsonEncode({
                ...payload,
                'defer_matching': true,
                'image_pending': imageBytes != null,
              }),
            )
            .timeout(const Duration(seconds: 30));
        if (response.statusCode >= 400 && response.statusCode < 500) {
          _creationUncertain = false;
        }
        if (response.statusCode != 201) {
          throw Exception(
            _message(
              response,
              'Unable to save the report. Check My Reports before retrying.',
            ),
          );
        }
        final body = jsonDecode(response.body);
        final item = body is Map ? body['item'] : null;
        final id = item is Map ? int.tryParse('${item['item_id']}') : null;
        if (id == null || id < 1) {
          throw Exception(
            'Report created without a valid ID. Check My Reports before starting a new report.',
          );
        }
        itemId = id;
        _savedPayload = encoded;
        publicationStatus = item['publication_status']?.toString();
        _creationUncertain = false;
      }
      _checkSession(token);
      if (!['PUBLISHED', 'PENDING_REVIEW'].contains(publicationStatus)) {
        throw Exception(
          'Report #$itemId is saved with an unexpected publication state. Check My Reports.',
        );
      }
      if (imageBytes != null && !listEquals(_uploadedBytes, imageBytes)) {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${AuthService.baseUrl}/items/$itemId/images'),
        );
        request.headers['Authorization'] = 'Bearer $token';
        request.fields['defer_matching'] = 'true';
        request.files.add(
          http.MultipartFile.fromBytes(
            'image',
            imageBytes,
            filename: imageName ?? 'item',
            contentType: MediaType.parse(mime!),
          ),
        );
        final response = await http.Response.fromStream(
          await request.send().timeout(const Duration(seconds: 40)),
        ).timeout(const Duration(seconds: 40));
        if (response.statusCode != 201) {
          throw Exception(
            'Report #$itemId is saved. ${_message(response, 'Image upload failed. Submit again to retry this report.')}',
          );
        }
        final body = jsonDecode(response.body);
        if (body is! Map ||
            body['image'] is! Map ||
            (int.tryParse('${body['image']['image_id']}') ?? 0) < 1 ||
            int.tryParse('${body['image']['item_id']}') != itemId) {
          throw Exception(
            'Report #$itemId is saved, but upload confirmation was invalid. Submit again to retry safely.',
          );
        }
        _uploadedBytes = Uint8List.fromList(imageBytes);
        publicationStatus =
            body['publication_status']?.toString() ?? publicationStatus;
      }
      _checkSession(token);
      if (publicationStatus == 'PUBLISHED') {
        final response = await http
            .post(
              Uri.parse('${AuthService.baseUrl}/matches/items/$itemId/run'),
              headers: AuthService.authenticatedHeaders(),
            )
            .timeout(const Duration(seconds: 130));
        if (response.statusCode != 200) {
          throw Exception(
            'Report #$itemId and its image are saved. ${_message(response, 'Matching failed. Submit again to retry matching only.')}',
          );
        }
      }
    } finally {
      _busy = false;
    }
  }

  void _checkSession(String token) {
    if (AuthService.authToken != token) {
      throw Exception('Session changed. Open My Reports to resume the report.');
    }
  }

  static String _message(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['message'] is String) return body['message'];
    } catch (_) {}
    return fallback;
  }
}
