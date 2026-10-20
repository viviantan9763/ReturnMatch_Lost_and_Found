import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AuthService {
  AuthService._();

  static String? authToken;
  static Map<String, dynamic>? currentUser;
  static const String baseUrl = 'http://localhost:3000/api';

  static String get _baseUrl {
    return kIsWeb
        ? 'http://localhost:3000/api'
        : 'http://10.0.2.2:3000/api';
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
      }),
    );

    final data = _decodeResponse(response);

    if (response.statusCode != 200) {
      throw Exception(data['message'] ?? 'Login failed');
    }

    authToken = data['token'] as String?;
    currentUser = data['user'] as Map<String, dynamic>?;

    return data;
  }

  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    String? phoneNo,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        'phone_no': phoneNo?.trim().isEmpty == true ? null : phoneNo?.trim(),
      }),
    );

    final data = _decodeResponse(response);

    if (response.statusCode != 201) {
      throw Exception(data['message'] ?? 'Registration failed');
    }

    return data;
  }

  static Map<String, dynamic> _decodeResponse(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}

    return {
      'message': 'Unexpected server response (${response.statusCode})',
    };
  }

  static Map<String, String> authenticatedHeaders() {
    return {
      'Content-Type': 'application/json',
      if (authToken != null) 'Authorization': 'Bearer $authToken',
    };
  }

  static void logout() {
    authToken = null;
    currentUser = null;
  }
}
