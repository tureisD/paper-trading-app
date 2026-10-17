import 'dart:convert';

import 'package:http/http.dart' as http;

/// Base failure from the GitHub API.
class GistException implements Exception {
  GistException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// Thrown on 403/429 when the primary rate limit is exhausted.
class RateLimitedException extends GistException {
  RateLimitedException(super.message, {this.resetAt, super.status});

  /// When the limiter resets, if GitHub told us.
  final DateTime? resetAt;

  @override
  String toString() => resetAt == null
      ? message
      : '$message (resets ${resetAt!.toLocal()})';
}

/// One file inside a gist.
class GistFile {
  const GistFile({
    required this.filename,
    required this.content,
    this.truncated = false,
    this.rawUrl,
  });

  final String filename;
  final String content;
  final bool truncated;
  final String? rawUrl;
}

/// A point-in-time view of a gist.
class GistSnapshot {
  const GistSnapshot({
    required this.id,
    required this.files,
    this.description,
    this.etag,
    this.updatedAt,
    this.notModified = false,
  });

  const GistSnapshot.notModified(this.id, {this.etag})
      : files = const {},
        description = null,
        updatedAt = null,
        notModified = true;

  final String id;
  final Map<String, GistFile> files;
  final String? description;
  final String? etag;
  final String? updatedAt;
  final bool notModified;
}

/// Identity + scopes of a token, used to explain 401/403s precisely.
class TokenInfo {
  const TokenInfo({
    required this.login,
    this.name,
    this.scopes = const [],
    this.scopesKnown = false,
  });

  final String login;
  final String? name;

  /// From `x-oauth-scopes`; empty for fine-grained tokens.
  final List<String> scopes;
  final bool scopesKnown;

  bool get hasGistScope => !scopesKnown || scopes.contains('gist');

  String get describe => scopesKnown
      ? '@$login • scopes: ${scopes.isEmpty ? 'none' : scopes.join(', ')}'
      : '@$login • fine-grained token';
}

/// Minimal Gist REST client (create/read/patch/delete) with ETag conditional
/// GETs and rate-limit translation.
class GistClient {
  GistClient({
    required this.token,
    http.Client? client,
    this.baseUrl = 'https://api.github.com',
  }) : _client = client ?? http.Client();

  final String token;
  final String baseUrl;
  final http.Client _client;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'TureisBanking',
      };

  /// Validates the token and reports who it belongs to and what it can do.
  ///
  /// `GET /user` costs no rate-limit budget concerns and returns the scopes in
  /// `x-oauth-scopes` for classic tokens (fine-grained tokens omit them).
  Future<TokenInfo> verifyToken() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/user'),
      headers: _headers,
    );
    _throwIfError(response);

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final scopeHeader = response.headers['x-oauth-scopes'];
    return TokenInfo(
      login: (body['login'] as String?) ?? 'unknown',
      name: body['name'] as String?,
      scopes: scopeHeader == null
          ? const []
          : scopeHeader
              .split(',')
              .map((scope) => scope.trim())
              .where((scope) => scope.isNotEmpty)
              .toList(growable: false),
      scopesKnown: scopeHeader != null,
    );
  }

  /// Conditional GET. Returns [GistSnapshot.notModified] on HTTP 304, which
  /// does not consume the primary rate limit.
  Future<GistSnapshot> getGist(String gistId, {String? etag}) async {
    final headers = {..._headers};
    if (etag != null && etag.isNotEmpty) headers['If-None-Match'] = etag;
    final response = await _client.get(
      Uri.parse('$baseUrl/gists/$gistId'),
      headers: headers,
    );
    if (response.statusCode == 304) {
      return GistSnapshot.notModified(gistId, etag: etag);
    }
    _throwIfError(response);
    return _parse(response);
  }

  Future<GistSnapshot> createGist({
    required Map<String, String> files,
    String? description,
    bool public = false,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/gists'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'description': description,
        'public': public,
        'files': {
          for (final entry in files.entries)
            entry.key: {'content': entry.value},
        },
      }),
    );
    _throwIfError(response);
    return _parse(response);
  }

  /// PATCHes only the named files; other files in the gist are untouched.
  Future<GistSnapshot> updateGist(
    String gistId, {
    required Map<String, String> files,
    String? description,
  }) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/gists/$gistId'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'description': ?description,
        'files': {
          for (final entry in files.entries)
            entry.key: {'content': entry.value},
        },
      }),
    );
    _throwIfError(response);
    return _parse(response);
  }

  Future<void> deleteGist(String gistId) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/gists/$gistId'),
      headers: _headers,
    );
    _throwIfError(response);
  }

  /// Remaining primary rate limit budget (does not itself consume budget).
  Future<Map<String, dynamic>> rateLimit() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/rate_limit'),
      headers: _headers,
    );
    _throwIfError(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void _throwIfError(http.Response response) {
    final code = response.statusCode;
    if ((code >= 200 && code < 300) || code == 304) return;

    if (code == 401) {
      throw GistException(
        'GitHub rejected the token (401 Bad credentials). It is invalid or '
        'expired.',
        status: code,
      );
    }
    if (code == 404) {
      throw GistException(
        'GitHub returned 404. Either the gist id is wrong, or the token lacks '
        'the Gists permission (fine-grained tokens need "Gists: read and write").',
        status: code,
      );
    }
    if (code == 403 || code == 429) {
      final remaining = response.headers['x-ratelimit-remaining'];
      final retryAfter = response.headers['retry-after'];
      final reset = response.headers['x-ratelimit-reset'];
      final limited = remaining == '0' || retryAfter != null || reset != null;

      if (!limited) {
        throw GistException(
          'GitHub refused the request (403). The token is valid but lacks the '
          'gist scope — classic tokens need "gist", fine-grained tokens need '
          '"Gists: read and write".',
          status: code,
        );
      }

      DateTime? resetAt;
      if (retryAfter != null) {
        final seconds = int.tryParse(retryAfter);
        if (seconds != null) {
          resetAt = DateTime.now().add(Duration(seconds: seconds));
        }
      } else if (reset != null) {
        final epoch = int.tryParse(reset);
        if (epoch != null) {
          resetAt = DateTime.fromMillisecondsSinceEpoch(
            epoch * 1000,
            isUtc: true,
          );
        }
      }
      throw RateLimitedException('GitHub rate limit reached', resetAt: resetAt, status: code);
    }
    throw GistException('GitHub request failed (HTTP $code)', status: code);
  }

  GistSnapshot _parse(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final filesJson = (body['files'] as Map?) ?? const {};
    final files = <String, GistFile>{};
    filesJson.forEach((key, value) {
      final map = (value as Map).cast<String, dynamic>();
      files['$key'] = GistFile(
        filename: '$key',
        content: (map['content'] as String?) ?? '',
        truncated: map['truncated'] == true,
        rawUrl: map['raw_url'] as String?,
      );
    });
    return GistSnapshot(
      id: (body['id'] as String?) ?? '',
      files: files,
      description: body['description'] as String?,
      etag: response.headers['etag'],
      updatedAt: body['updated_at'] as String?,
    );
  }
}
