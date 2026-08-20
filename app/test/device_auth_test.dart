/// OAuth 2.0 device flow (RFC 8628) against a fake http client — no network.
///
/// The interesting behaviour is the polling loop: `authorization_pending`
/// keeps waiting, `slow_down` adds 5 s to the interval, and only then does the
/// success response arrive.
library;

import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tally/core/constants.dart';
import 'package:tally/data/drive/device_auth.dart';

/// Collects the durations the client would have slept, so the test runs
/// instantly and can still assert on the back-off. [now] is a virtual wall
/// clock that every faked sleep advances, so a poll deadline is reachable
/// without the test actually waiting for it.
class _Clock {
  _Clock({DateTime? start}) : now = start ?? DateTime.utc(2026, 8, 20, 12);

  DateTime now;
  final List<Duration> sleeps = <Duration>[];

  Future<void> sleep(Duration d) async {
    sleeps.add(d);
    now = now.add(d);
  }
}

DeviceAuthClient _client(
  MockClient http, {
  _Clock? clock,
  DateTime Function()? now,
}) =>
    DeviceAuthClient(
      httpClient: http,
      clientId: 'test-client-id',
      clientSecret: 'test-client-secret',
      sleep: (clock ?? _Clock()).sleep,
      clock: now,
    );

/// A prompt whose user code dies at [at] — the only deadline that may end a
/// poll loop besides a denial or an explicit cancel.
DeviceAuthPrompt _promptExpiringAt(DateTime at) => DeviceAuthPrompt(
      deviceCode: 'DC-123',
      userCode: 'FJHQ-XMKN',
      verificationUrl: 'https://www.google.com/device',
      interval: const Duration(seconds: 5),
      expiresAt: at,
    );

http.Response _json(Map<String, Object?> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: const <String, String>{
          'content-type': 'application/json',
        });

void main() {
  group('requestCode', () {
    test('parses the device code response', () async {
      late Map<String, String> sentForm;
      final DeviceAuthClient auth = _client(MockClient((http.Request r) async {
        expect(r.url.toString(), DriveOAuth.deviceCodeEndpoint);
        sentForm = Uri.splitQueryString(r.body);
        return _json(<String, Object?>{
          'device_code': 'DC-123',
          'user_code': 'FJHQ-XMKN',
          'verification_url': 'https://www.google.com/device',
          'expires_in': 1800,
          'interval': 5,
        });
      }));

      final DeviceAuthPrompt prompt = await auth.requestCode();

      expect(sentForm['client_id'], 'test-client-id');
      expect(sentForm['scope'], DriveOAuth.scope);
      expect(prompt.deviceCode, 'DC-123');
      expect(prompt.userCode, 'FJHQ-XMKN');
      expect(prompt.verificationUrl, 'https://www.google.com/device');
      expect(prompt.interval, const Duration(seconds: 5));
      expect(prompt.remaining(DateTime.now()).inMinutes, greaterThan(25));
    });

    test('accepts the RFC 8628 verification_uri spelling too', () async {
      final DeviceAuthClient auth = _client(MockClient((_) async => _json(
            <String, Object?>{
              'device_code': 'DC',
              'user_code': 'AAAA-BBBB',
              'verification_uri': 'https://example.test/device',
            },
          )));
      final DeviceAuthPrompt prompt = await auth.requestCode();
      expect(prompt.verificationUrl, 'https://example.test/device');
      expect(prompt.interval, const Duration(seconds: 5)); // default
    });

    test('a build with no OAuth client refuses before any request', () async {
      final DeviceAuthClient auth = DeviceAuthClient(
        httpClient: MockClient((_) async => fail('must not call Google')),
        clientId: '',
        clientSecret: '',
      );
      expect(auth.isAvailable, isFalse);
      await expectLater(
        auth.requestCode(),
        throwsA(isA<DeviceAuthException>().having(
            (e) => e.code, 'code', DeviceAuthException.notAvailable)),
      );
    });
  });

  group('pollForTokens', () {
    final DeviceAuthPrompt prompt = DeviceAuthPrompt(
      deviceCode: 'DC-123',
      userCode: 'FJHQ-XMKN',
      verificationUrl: 'https://www.google.com/device',
      interval: const Duration(seconds: 5),
      expiresAt: DateTime.now().add(const Duration(minutes: 30)),
    );

    test('pending -> slow_down -> success, honouring both signals', () async {
      final _Clock clock = _Clock();
      final List<Map<String, String>> forms = <Map<String, String>>[];
      int call = 0;
      final DeviceAuthClient auth = _client(
        MockClient((http.Request r) async {
          expect(r.url.toString(), DriveOAuth.tokenEndpoint);
          forms.add(Uri.splitQueryString(r.body));
          call++;
          return switch (call) {
            // Google answers the device grant's "keep waiting" with 4xx.
            1 => _json(
                <String, Object?>{'error': 'authorization_pending'}, 428),
            2 => _json(<String, Object?>{'error': 'slow_down'}, 403),
            _ => _json(<String, Object?>{
                'access_token': 'ya29.access',
                'refresh_token': '1//refresh',
                'expires_in': 3599,
                'token_type': 'Bearer',
              }),
          };
        }),
        clock: clock,
      );

      final List<int> attempts = <int>[];
      final DeviceTokens tokens = await auth.pollForTokens(
        prompt,
        onAttempt: attempts.add,
      );

      expect(call, 3);
      expect(attempts, <int>[1, 2, 3]);
      // 5 s, 5 s, then +5 s after slow_down.
      expect(clock.sleeps, <Duration>[
        const Duration(seconds: 5),
        const Duration(seconds: 5),
        const Duration(seconds: 10),
      ]);
      expect(tokens.accessToken, 'ya29.access');
      expect(tokens.refreshToken, '1//refresh');
      expect(tokens.expiresAt.isAfter(DateTime.now()), isTrue);

      // Every poll carries the device-code grant and the full client creds.
      for (final Map<String, String> f in forms) {
        expect(f['grant_type'], DriveOAuth.deviceCodeGrantType);
        expect(f['device_code'], 'DC-123');
        expect(f['client_id'], 'test-client-id');
        expect(f['client_secret'], 'test-client-secret');
      }
    });

    test('access_denied stops immediately and asks for re-authorization',
        () async {
      int call = 0;
      final DeviceAuthClient auth = _client(MockClient((_) async {
        call++;
        return _json(<String, Object?>{
          'error': 'access_denied',
          'error_description': 'user refused',
        }, 403);
      }));

      await expectLater(
        auth.pollForTokens(prompt),
        throwsA(isA<DeviceAuthException>()
            .having((e) => e.code, 'code', DeviceAuthException.denied)
            .having((e) => e.needsReauthorization, 'needsReauth', isTrue)),
      );
      expect(call, 1);
    });

    test('expired_token from the server surfaces as expired', () async {
      final DeviceAuthClient auth = _client(MockClient(
          (_) async => _json(<String, Object?>{'error': 'expired_token'}, 400)));
      await expectLater(
        auth.pollForTokens(prompt),
        throwsA(isA<DeviceAuthException>()
            .having((e) => e.code, 'code', DeviceAuthException.expired)),
      );
    });

    test('a prompt that already expired never hits the network', () async {
      final DeviceAuthClient auth = _client(
        MockClient((_) async => fail('must not poll an expired prompt')),
      );
      final DeviceAuthPrompt dead = DeviceAuthPrompt(
        deviceCode: 'DC',
        userCode: 'X',
        verificationUrl: 'https://www.google.com/device',
        interval: const Duration(seconds: 5),
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      await expectLater(
        auth.pollForTokens(dead),
        throwsA(isA<DeviceAuthException>()
            .having((e) => e.code, 'code', DeviceAuthException.expired)),
      );
    });

    test('cancellation aborts the loop', () async {
      int call = 0;
      final DeviceAuthClient auth = _client(MockClient((_) async {
        call++;
        return _json(
            <String, Object?>{'error': 'authorization_pending'}, 428);
      }));

      bool cancelled = false;
      await expectLater(
        auth.pollForTokens(
          prompt,
          isCancelled: () => cancelled,
          onAttempt: (_) => cancelled = true,
        ),
        throwsA(isA<DeviceAuthException>()
            .having((e) => e.code, 'code', DeviceAuthException.cancelled)),
      );
      expect(call, 1);
    });

    test('a transient network drop keeps polling instead of aborting',
        () async {
      // Regression: the user is sent to a browser, so this app is backgrounded
      // and its sockets die routinely. One dropped request used to abort the
      // whole authorization and force a brand-new code, even though the one on
      // screen stays valid for ~30 minutes.
      final _Clock clock = _Clock();
      int call = 0;
      final DeviceAuthClient auth = _client(
        MockClient((_) async {
          call++;
          if (call == 1) throw http.ClientException('connection reset');
          if (call == 2) throw const SocketException('network is unreachable');
          return _json(<String, Object?>{
            'access_token': 'ya29.access',
            'refresh_token': '1//refresh',
            'expires_in': 3599,
          });
        }),
        clock: clock,
        now: () => clock.now,
      );

      final DeviceTokens tokens = await auth.pollForTokens(
        _promptExpiringAt(clock.now.add(const Duration(minutes: 30))),
      );

      expect(call, 3);
      expect(tokens.accessToken, 'ya29.access');
      expect(tokens.refreshToken, '1//refresh');
      // 5 s base, then the base plus a growing network back-off (5 s, 10 s).
      expect(clock.sleeps, <Duration>[
        const Duration(seconds: 5),
        const Duration(seconds: 10),
        const Duration(seconds: 15),
      ]);
    });

    test('a permanent outage still ends when the code expires', () async {
      final _Clock clock = _Clock();
      int call = 0;
      final DeviceAuthClient auth = _client(
        MockClient((_) async {
          call++;
          throw http.ClientException('offline');
        }),
        clock: clock,
        now: () => clock.now,
      );

      await expectLater(
        auth.pollForTokens(
          _promptExpiringAt(clock.now.add(const Duration(minutes: 30))),
        ),
        throwsA(isA<DeviceAuthException>()
            .having((e) => e.code, 'code', DeviceAuthException.expired)),
      );
      // It kept trying for the code's whole lifetime instead of giving up on
      // the first failure, at a capped 5 s + 30 s pace.
      expect(call, greaterThan(10));
      expect(clock.sleeps.last, const Duration(seconds: 35));
    });

    test('cancellation still wins over a dead network', () async {
      final _Clock clock = _Clock();
      bool cancelled = false;
      final DeviceAuthClient auth = _client(
        MockClient((_) async {
          cancelled = true;
          throw http.ClientException('offline');
        }),
        clock: clock,
        now: () => clock.now,
      );
      await expectLater(
        auth.pollForTokens(
          _promptExpiringAt(clock.now.add(const Duration(minutes: 30))),
          isCancelled: () => cancelled,
        ),
        throwsA(isA<DeviceAuthException>()
            .having((e) => e.code, 'code', DeviceAuthException.cancelled)),
      );
    });
  });

  group('refreshAccessToken', () {
    test('exchanges the refresh token and reports rotation', () async {
      late Map<String, String> form;
      final DeviceAuthClient auth = _client(MockClient((http.Request r) async {
        form = Uri.splitQueryString(r.body);
        return _json(<String, Object?>{
          'access_token': 'ya29.fresh',
          'refresh_token': '1//rotated',
          'expires_in': 3599,
        });
      }));

      final DeviceTokens tokens = await auth.refreshAccessToken('1//old');

      expect(form['grant_type'], 'refresh_token');
      expect(form['refresh_token'], '1//old');
      expect(tokens.accessToken, 'ya29.fresh');
      expect(tokens.refreshToken, '1//rotated');
    });

    test('a revoked grant is reported as needing re-authorization', () async {
      final DeviceAuthClient auth = _client(MockClient((_) async => _json(
            <String, Object?>{
              'error': 'invalid_grant',
              'error_description': 'Token has been expired or revoked.',
            },
            400,
          )));
      await expectLater(
        auth.refreshAccessToken('1//dead'),
        throwsA(isA<DeviceAuthException>()
            .having((e) => e.code, 'code', DeviceAuthException.revoked)
            .having((e) => e.needsReauthorization, 'needsReauth', isTrue)),
      );
    });

    test('a dead network fails fast — the engine owns the retry', () async {
      int calls = 0;
      final DeviceAuthClient auth = _client(MockClient((_) async {
        calls++;
        throw http.ClientException('connection failed');
      }));
      await expectLater(
        auth.refreshAccessToken('1//keep'),
        throwsA(isA<DeviceAuthException>()
            .having((e) => e.code, 'code', 'network')
            .having((e) => e.needsReauthorization, 'needsReauth', isFalse)),
      );
      expect(calls, 1); // unlike pollForTokens, this one does NOT loop
    });

    test('no rotation means refreshToken is null', () async {
      final DeviceAuthClient auth = _client(MockClient((_) async => _json(
            <String, Object?>{'access_token': 'ya29.fresh', 'expires_in': 60},
          )));
      final DeviceTokens tokens = await auth.refreshAccessToken('1//keep');
      expect(tokens.refreshToken, isNull);
    });
  });

  test('revoke never throws', () async {
    final DeviceAuthClient auth = _client(
        MockClient((_) async => throw http.ClientException('offline')));
    await auth.revoke('1//whatever'); // must not throw
  });
}
