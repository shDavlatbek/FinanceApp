/// OAuth 2.0 Device Authorization Grant (RFC 8628) against Google, over plain
/// `package:http`.
///
/// Deliberately *not* `google_sign_in`: the app and the Go server share ONE
/// OAuth client of type "TVs and Limited Input devices" and each runs its own
/// device authorization for the same Google account. That removes every piece
/// of Android/iOS native OAuth configuration — no SHA-1 registration, no
/// reversed-client-id URL scheme, no `google-services.json`.
///
/// Flow (docs/ARCHITECTURE.md § Auth):
/// 1. `POST /device/code` -> device_code, user_code, verification_url, interval
/// 2. show the user the URL + code
/// 3. poll `POST /token`, honouring `authorization_pending` and `slow_down`
/// 4. persist the refresh token
/// 5. refresh tokens rotate — persist a new one whenever it appears
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../../core/constants.dart';

/// A failure of the device flow or of a token refresh.
///
/// [code] is the machine-readable OAuth error (`access_denied`,
/// `expired_token`, `invalid_grant`, `slow_down`, …) or one of the synthetic
/// codes below.
class DeviceAuthException implements Exception {
  const DeviceAuthException(this.code, this.message);

  /// The app was built without `--dart-define=GOOGLE_CLIENT_ID/SECRET`.
  static const String notAvailable = 'client_not_configured';

  /// The user code expired before it was approved.
  static const String expired = 'expired_token';

  /// The user denied the request at google.com/device.
  static const String denied = 'access_denied';

  /// The stored refresh token was revoked — full re-authorization needed.
  static const String revoked = 'invalid_grant';

  /// [cancelAuthorization] was called while polling.
  static const String cancelled = 'cancelled';

  final String code;
  final String message;

  /// True when the only way forward is a fresh device authorization.
  bool get needsReauthorization =>
      code == revoked || code == denied || code == expired;

  @override
  String toString() => 'DeviceAuthException($code): $message';
}

/// What the UI must show the user: open [verificationUrl] and type [userCode].
class DeviceAuthPrompt {
  const DeviceAuthPrompt({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.interval,
    required this.expiresAt,
  });

  /// Secret polled against the token endpoint. Never show this.
  final String deviceCode;

  /// Short code the user types, e.g. `FJHQ-XMKN`.
  final String userCode;

  /// Where the user types it, e.g. `https://www.google.com/device`.
  final String verificationUrl;

  /// Minimum poll interval requested by the server.
  final Duration interval;

  /// Wall-clock deadline after which [userCode] stops working.
  final DateTime expiresAt;

  Duration remaining(DateTime now) {
    final Duration left = expiresAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}

/// A successful token exchange. [refreshToken] is null only when Google
/// declined to rotate one on a plain refresh call.
class DeviceTokens {
  const DeviceTokens({
    required this.accessToken,
    required this.expiresAt,
    this.refreshToken,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
}

/// Device-flow + refresh client. Stateless: it holds no tokens, the sync
/// engine owns persistence.
///
/// Subclass and override [requestCode] / [pollForTokens] /
/// [refreshAccessToken] to fake it in tests, or inject an
/// `http.Client` (e.g. `MockClient`) to exercise the real polling logic.
class DeviceAuthClient {
  DeviceAuthClient({
    http.Client? httpClient,
    this._clientId = DriveOAuth.clientId,
    this._clientSecret = DriveOAuth.clientSecret,
    Future<void> Function(Duration)? sleep,
    DateTime Function()? clock,
    this._timeout = const Duration(seconds: 30),
  })  : _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null,
        _sleep = sleep ?? Future<void>.delayed,
        _clock = clock ?? DateTime.now;

  final http.Client _http;
  final bool _ownsHttp;
  final String _clientId;
  final String _clientSecret;
  final Future<void> Function(Duration) _sleep;
  final DateTime Function() _clock;
  final Duration _timeout;

  /// False when the build has no OAuth client compiled in.
  bool get isAvailable => _clientId.isNotEmpty && _clientSecret.isNotEmpty;

  /// Step 1 — asks Google for a device code and the user-facing code/URL.
  Future<DeviceAuthPrompt> requestCode() async {
    _requireClient();
    final Map<String, Object?> json = await _post(
      DriveOAuth.deviceCodeEndpoint,
      <String, String>{
        'client_id': _clientId,
        'scope': DriveOAuth.scope,
      },
    );
    final String? deviceCode = json['device_code'] as String?;
    final String? userCode = json['user_code'] as String?;
    // Google returns `verification_url`; RFC 8628 names it `verification_uri`.
    final String? url = (json['verification_url'] ?? json['verification_uri'])
        as String?;
    if (deviceCode == null || userCode == null || url == null) {
      throw const DeviceAuthException(
          'invalid_response', 'Device code response was incomplete');
    }
    final int intervalSec = (json['interval'] as num?)?.toInt() ?? 5;
    final int expiresIn = (json['expires_in'] as num?)?.toInt() ?? 1800;
    return DeviceAuthPrompt(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUrl: url,
      interval: Duration(seconds: intervalSec),
      expiresAt: _clock().add(Duration(seconds: expiresIn)),
    );
  }

  /// Extra wait added after the first failed request, doubled on every further
  /// consecutive network failure and capped at [maxNetworkRetryDelay].
  static const Duration networkRetryDelay = Duration(seconds: 5);
  static const Duration maxNetworkRetryDelay = Duration(seconds: 30);

  /// Step 3 — polls until the user approves.
  ///
  /// * `authorization_pending` -> keep waiting at the current interval
  /// * `slow_down`             -> add 5 s to the interval, keep waiting
  /// * a network failure       -> keep waiting, backing the interval off
  /// * `access_denied` / `expired_token` -> [DeviceAuthException]
  ///
  /// A dropped connection is the *expected* state here, not a failure: the
  /// user has been sent to a browser in another app, so this one is
  /// backgrounded and its sockets die routinely. The device code stays valid
  /// for ~30 minutes, so only [DeviceAuthPrompt.expiresAt], an explicit
  /// denial/expiry from Google, or [isCancelled] end the loop — never a single
  /// lost packet, which would otherwise force the user to start over and type
  /// a brand-new code. ([refreshAccessToken] stays fail-fast: the sync engine
  /// retries whole passes itself.)
  ///
  /// [isCancelled] is checked before every request and after every wait so the
  /// UI can abort. [onAttempt] fires once per poll for live progress.
  Future<DeviceTokens> pollForTokens(
    DeviceAuthPrompt prompt, {
    bool Function()? isCancelled,
    void Function(int attempt)? onAttempt,
  }) async {
    _requireClient();
    Duration interval = prompt.interval;
    Duration retryDelay = Duration.zero;
    int attempt = 0;
    while (true) {
      if (isCancelled?.call() ?? false) {
        throw const DeviceAuthException(
            DeviceAuthException.cancelled, 'Authorization cancelled');
      }
      if (!_clock().isBefore(prompt.expiresAt)) {
        throw const DeviceAuthException(
            DeviceAuthException.expired, 'The code expired — start again');
      }
      await _sleep(interval + retryDelay);
      if (isCancelled?.call() ?? false) {
        throw const DeviceAuthException(
            DeviceAuthException.cancelled, 'Authorization cancelled');
      }
      attempt++;
      onAttempt?.call(attempt);

      final Map<String, Object?> json;
      try {
        json = await _post(
          DriveOAuth.tokenEndpoint,
          <String, String>{
            'client_id': _clientId,
            'client_secret': _clientSecret,
            'device_code': prompt.deviceCode,
            'grant_type': DriveOAuth.deviceCodeGrantType,
          },
          allowErrorBody: true,
        );
      } on DeviceAuthException catch (e) {
        if (e.code != 'network') rethrow;
        retryDelay = _nextRetryDelay(retryDelay);
        continue; // the loop re-checks cancellation and the code's deadline
      }
      retryDelay = Duration.zero; // Google answered — back to the base pace

      final String? error = json['error'] as String?;
      if (error == null) return _tokensFrom(json);
      switch (error) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          interval += const Duration(seconds: 5);
          continue;
        default:
          throw DeviceAuthException(
            error,
            (json['error_description'] as String?) ?? error,
          );
      }
    }
  }

  /// Step 5 — exchanges the long-lived refresh token for an access token.
  /// The returned [DeviceTokens.refreshToken] is non-null only when Google
  /// rotated it; callers must persist it when it is.
  Future<DeviceTokens> refreshAccessToken(String refreshToken) async {
    _requireClient();
    final Map<String, Object?> json = await _post(
      DriveOAuth.tokenEndpoint,
      <String, String>{
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'refresh_token': refreshToken,
        'grant_type': 'refresh_token',
      },
      allowErrorBody: true,
    );
    final String? error = json['error'] as String?;
    if (error != null) {
      throw DeviceAuthException(
        error,
        (json['error_description'] as String?) ?? error,
      );
    }
    return _tokensFrom(json);
  }

  /// Best-effort revocation on disconnect. Never throws.
  Future<void> revoke(String token) async {
    try {
      await _http
          .post(
            Uri.parse(DriveOAuth.revokeEndpoint),
            headers: const <String, String>{
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: <String, String>{'token': token},
          )
          .timeout(_timeout);
    } catch (_) {
      // Revocation is a courtesy; the local token is dropped either way.
    }
  }

  void close() {
    if (_ownsHttp) _http.close();
  }

  // ---- internals ----------------------------------------------------------

  /// Exponential back-off for consecutive network failures while polling,
  /// capped so a long outage still checks in twice a minute.
  static Duration _nextRetryDelay(Duration current) {
    final Duration next =
        current == Duration.zero ? networkRetryDelay : current * 2;
    return next > maxNetworkRetryDelay ? maxNetworkRetryDelay : next;
  }

  void _requireClient() {
    if (!isAvailable) {
      throw const DeviceAuthException(
        DeviceAuthException.notAvailable,
        'This build has no Google OAuth client compiled in '
        '(--dart-define=GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET).',
      );
    }
  }

  DeviceTokens _tokensFrom(Map<String, Object?> json) {
    final String? accessToken = json['access_token'] as String?;
    if (accessToken == null) {
      throw const DeviceAuthException(
          'invalid_response', 'Token response had no access_token');
    }
    final int expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    return DeviceTokens(
      accessToken: accessToken,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: _clock().add(Duration(seconds: expiresIn)),
    );
  }

  /// Form-encoded POST returning the decoded JSON body.
  ///
  /// With [allowErrorBody] a 4xx whose body carries an OAuth `error` is
  /// returned instead of thrown — the device-grant "keep polling" responses
  /// arrive as HTTP 428/400.
  Future<Map<String, Object?>> _post(
    String url,
    Map<String, String> form, {
    bool allowErrorBody = false,
  }) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse(url),
            headers: const <String, String>{
              'Content-Type': 'application/x-www-form-urlencoded',
              'Accept': 'application/json',
            },
            body: form,
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const DeviceAuthException('network', 'Google did not respond');
    } on SocketException catch (e) {
      throw DeviceAuthException('network', 'No connection: ${e.message}');
    } on http.ClientException catch (e) {
      throw DeviceAuthException('network', 'No connection: ${e.message}');
    }

    Map<String, Object?>? body;
    try {
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, Object?>) body = decoded;
    } catch (_) {
      body = null;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body == null) {
        throw const DeviceAuthException(
            'invalid_response', 'Google returned a non-JSON body');
      }
      return body;
    }
    if (allowErrorBody && body != null && body['error'] is String) {
      return body;
    }
    throw DeviceAuthException(
      (body?['error'] as String?) ?? 'http_${response.statusCode}',
      (body?['error_description'] as String?) ??
          'HTTP ${response.statusCode} from Google',
    );
  }
}
