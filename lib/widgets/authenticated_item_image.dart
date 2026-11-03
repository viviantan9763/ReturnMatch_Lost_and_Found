import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';

// Fetch bytes with bearer authentication on Web as well as Android. Browser
// image elements cannot consistently attach custom Authorization headers.
class AuthenticatedItemImage extends StatefulWidget {
  const AuthenticatedItemImage({
    super.key,
    required this.url,
    required this.placeholder,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
  });
  final String url;
  final Widget placeholder;
  final double? height;
  final double? width;
  final BoxFit fit;
  @override
  State<AuthenticatedItemImage> createState() => _AuthenticatedItemImageState();
}

class _AuthenticatedItemImageState extends State<AuthenticatedItemImage> {
  late Future<Uint8List?> _image;
  String? _token;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant AuthenticatedItemImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || _token != AuthService.authToken) {
      _reload();
    }
  }

  void _reload() {
    _token = AuthService.authToken;
    _image = _load(widget.url, _token);
  }

  Future<Uint8List?> _load(String url, String? token) async {
    try {
      final base = Uri.parse(AuthService.baseUrl);
      final uri = Uri.parse(url);
      if (token == null ||
          uri.origin != base.origin ||
          !RegExp(r'^/api/items/\d+/images/\d+$').hasMatch(uri.path)) {
        return null;
      }
      final response = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 ||
          token != AuthService.authToken ||
          ![
            'image/jpeg',
            'image/png',
            'image/webp',
          ].contains(response.headers['content-type']?.split(';').first) ||
          response.bodyBytes.length > 5 * 1024 * 1024) {
        return null;
      }
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _image,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done ||
          snapshot.data == null ||
          AuthService.authToken != _token) {
        return widget.placeholder;
      }
      return Image.memory(
        snapshot.data!,
        fit: widget.fit,
        height: widget.height,
        width: widget.width,
        errorBuilder: (_, _, _) => widget.placeholder,
      );
    },
  );
}
