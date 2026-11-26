import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/ids.dart';
import 'models.dart';

/// Token 与签名密钥的安全存储。App 内实现为 Keychain / Keystore，单测用内存实现。
abstract class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class MemoryTokenStore implements TokenStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

/// 登录 / 注册失败原因。业务层只给错误码，文案由界面按当前语言决定（见 `S.authError`）。
enum AuthError { invalidUsername, passwordTooShort, usernameTaken, wrongCredentials }

class AuthException implements Exception {
  const AuthException(this.error);
  final AuthError error;
  @override
  String toString() => 'AuthException(${error.name})';
}

/// 本地 Mock 鉴权。
///
/// - 账号：存 users 表，密码为「随机盐 + SHA-256 迭代 [_hashRounds] 轮」，不存明文。
/// - Token：`base64url(payload) . base64url(HMAC-SHA256(payload, secret))`，
///   payload = {sub 用户 id, jti 会话 id, iat 签发时间, exp 过期时间}，结构同 JWT。
///   secret 为安装时随机生成的 32 字节，存安全存储。
/// - 校验（[restore]）：① 签名正确 ② 未过期 ③ sessions 表存在该 jti 且未吊销 ④ 用户存在。
///   四项全过才恢复登录态；登出会吊销 jti，旧 Token 立即失效。
class AuthService {
  AuthService(this._db, this._store, {this.now = systemNow});

  final Database _db;
  final TokenStore _store;
  final NowFn now;

  static const _tokenKey = 'auth_token';
  static const _secretKey = 'auth_secret';
  static const _hashRounds = 2000;
  static const tokenTtl = Duration(days: 30);

  static const demoUsername = 'demo';
  static const demoPassword = 'demo1234';

  final ValueNotifier<AppUser?> currentUser = ValueNotifier(null);

  String get userId => currentUser.value?.id ?? '';

  /// 首次启动内置一个演示账号，方便评审直接登录。
  Future<void> ensureDemoAccount() async {
    final rows = await _db.query('users', where: 'username = ?', whereArgs: [demoUsername], limit: 1);
    if (rows.isEmpty) await _createUser(demoUsername, demoPassword);
  }

  Future<AppUser> register(String username, String password) async {
    final name = username.trim();
    if (!RegExp(r'^[A-Za-z0-9_]{3,20}$').hasMatch(name)) {
      throw const AuthException(AuthError.invalidUsername);
    }
    if (password.length < 6) {
      throw const AuthException(AuthError.passwordTooShort);
    }
    final exists = await _db.query('users', where: 'username = ?', whereArgs: [name], limit: 1);
    if (exists.isNotEmpty) throw const AuthException(AuthError.usernameTaken);
    await _createUser(name, password);
    return login(name, password);
  }

  Future<AppUser> login(String username, String password) async {
    final rows = await _db.query('users', where: 'username = ?', whereArgs: [username.trim()], limit: 1);
    if (rows.isEmpty) throw const AuthException(AuthError.wrongCredentials);
    final row = rows.first;
    final expected = row['password_hash'] as String;
    final actual = _hash(password, row['salt'] as String);
    if (!_constantTimeEquals(expected, actual)) throw const AuthException(AuthError.wrongCredentials);

    final user = AppUser(id: row['id'] as String, username: row['username'] as String);
    final token = await _issueToken(user.id);
    await _store.write(_tokenKey, token);
    currentUser.value = user;
    return user;
  }

  /// 冷启动时调用：校验本地 Token，通过则恢复登录态。
  Future<AppUser?> restore() async {
    final token = await _store.read(_tokenKey);
    if (token == null) return null;
    final user = await verify(token);
    if (user == null) await _store.delete(_tokenKey);
    currentUser.value = user;
    return user;
  }

  Future<AppUser?> verify(String token) async {
    final parts = token.split('.');
    if (parts.length != 2) return null;
    final secret = await _store.read(_secretKey);
    if (secret == null) return null;
    if (!_constantTimeEquals(_sign(parts[0], secret), parts[1])) return null;

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[0])))) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    final nowMs = now().millisecondsSinceEpoch;
    if ((payload['exp'] as int? ?? 0) <= nowMs) return null;

    final sessions = await _db.query(
      'sessions',
      where: 'jti = ? AND revoked = 0 AND expires_at > ?',
      whereArgs: [payload['jti'], nowMs],
      limit: 1,
    );
    if (sessions.isEmpty) return null;
    final users = await _db.query('users', where: 'id = ?', whereArgs: [payload['sub']], limit: 1);
    if (users.isEmpty) return null;
    return AppUser(id: users.first['id'] as String, username: users.first['username'] as String);
  }

  Future<void> logout() async {
    final token = await _store.read(_tokenKey);
    if (token != null) {
      try {
        final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(token.split('.').first))),
        ) as Map<String, dynamic>;
        await _db.update('sessions', {'revoked': 1}, where: 'jti = ?', whereArgs: [payload['jti']]);
      } catch (_) {}
    }
    await _store.delete(_tokenKey);
    currentUser.value = null;
  }

  Future<String?> currentToken() => _store.read(_tokenKey);

  // ---- internals ----

  Future<void> _createUser(String username, String password) async {
    final salt = _randomBase64(16);
    await _db.insert('users', {
      'id': uuidV4(),
      'username': username,
      'password_hash': _hash(password, salt),
      'salt': salt,
      'created_at': now().millisecondsSinceEpoch,
    });
  }

  Future<String> _issueToken(String userId) async {
    var secret = await _store.read(_secretKey);
    if (secret == null) {
      secret = _randomBase64(32);
      await _store.write(_secretKey, secret);
    }
    final nowMs = now().millisecondsSinceEpoch;
    final exp = nowMs + tokenTtl.inMilliseconds;
    final jti = uuidV4();
    await _db.insert('sessions', {'jti': jti, 'user_id': userId, 'issued_at': nowMs, 'expires_at': exp});
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({'sub': userId, 'jti': jti, 'iat': nowMs, 'exp': exp})))
        .replaceAll('=', '');
    return '$payload.${_sign(payload, secret)}';
  }

  static String _sign(String payload, String secret) =>
      base64Url.encode(Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(payload)).bytes).replaceAll('=', '');

  static String _hash(String password, String salt) {
    final saltBytes = utf8.encode(salt);
    var digest = sha256.convert([...saltBytes, ...utf8.encode(password)]).bytes;
    for (var i = 0; i < _hashRounds; i++) {
      digest = sha256.convert([...digest, ...saltBytes]).bytes;
    }
    return base64Url.encode(digest);
  }

  static String _randomBase64(int bytes) {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(bytes, (_) => r.nextInt(256)));
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
