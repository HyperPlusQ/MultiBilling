import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// 口令散列。
///
/// 实验二设计指定 BCrypt，但 Dart 标准库与常用第一方包中没有纯 Dart 的
/// BCrypt 实现。为了不引入原生依赖，这里使用「随机盐 + 迭代 SHA-256」，
/// 同样能抵抗彩虹表；迭代次数刻意设高以逼近慢哈希的效果。
/// 这是实现层对设计的一处有意替换，报告中已记录。
class PasswordHasher {
  /// 迭代次数。
  static const int iterations = 20000;

  static final Random _random = Random.secure();

  /// 生成 16 字节随机盐的 base64 表示。
  static String newSalt() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Encode(bytes);
  }

  /// 计算散列，返回 `格式$盐$散列` 便于日后升级算法。
  static String hash(String password, String salt) {
    var digest = sha256.convert(utf8.encode('$salt:$password'));
    for (var i = 1; i < iterations; i++) {
      digest = sha256.convert(utf8.encode('$salt:${digest.toString()}'));
    }
    return 'pbkdf2-like-sha256#$iterations'
        r'$'
        '$salt'
        r'$'
        '${digest.toString()}';
  }

  /// 校验口令，比对时不提前返回以减小计时侧信道。
  static bool verify(String password, String stored) {
    final parts = stored.split(r'$');
    if (parts.length != 3) {
      return false;
    }
    final candidate = hash(password, parts[1]);
    return _constantTimeEquals(candidate, stored);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
