import 'package:flutter_test/flutter_test.dart';
import 'package:multibilling/domain/operation_log.dart';

/// 操作存档哈希链测试：规范化 JSON、哈希确定性、篡改检测。
OperationLog buildLog({
  required String prevHash,
  Map<String, Object?> detail = const <String, Object?>{'k': 'v'},
  int logId = 1,
}) {
  final createdAt = DateTime(2026, 11, 13, 10);
  final hash = OperationLog.computeHash(
    prevHash: prevHash,
    ledgerId: 1,
    operatorId: 2,
    action: 'ENTRY_SUBMIT',
    targetType: 'Entry',
    targetId: 3,
    detail: detail,
    createdAt: createdAt,
  );
  return OperationLog(
    logId: logId,
    ledgerId: 1,
    operatorId: 2,
    action: 'ENTRY_SUBMIT',
    targetType: 'Entry',
    targetId: 3,
    detail: detail,
    prevHash: prevHash,
    hash: hash,
    createdAt: createdAt,
  );
}

void main() {
  group('canonicalJson', () {
    test('键按字典序排序，与插入顺序无关', () {
      final a = OperationLog.canonicalJson(<String, Object?>{
        'b': 2,
        'a': 1,
        'c': 3,
      });
      final b = OperationLog.canonicalJson(<String, Object?>{
        'c': 3,
        'a': 1,
        'b': 2,
      });
      expect(a, b);
      expect(a, '{"a":1,"b":2,"c":3}');
    });

    test('空 map 得到 {}', () {
      expect(OperationLog.canonicalJson(<String, Object?>{}), '{}');
    });
  });

  group('computeHash', () {
    test('相同输入得到相同哈希', () {
      final h1 = buildLog(prevHash: OperationLog.genesisHash).hash;
      final h2 = buildLog(prevHash: OperationLog.genesisHash).hash;
      expect(h1, h2);
      expect(h1.length, 64); // SHA-256 十六进制
    });

    test('前驱哈希不同则本条哈希不同', () {
      final h1 = buildLog(prevHash: OperationLog.genesisHash).hash;
      final h2 = buildLog(prevHash: 'f' * 64).hash;
      expect(h1, isNot(h2));
    });

    test('明细不同则哈希不同', () {
      final h1 = buildLog(
        prevHash: OperationLog.genesisHash,
        detail: <String, Object?>{'amount': '100.00'},
      ).hash;
      final h2 = buildLog(
        prevHash: OperationLog.genesisHash,
        detail: <String, Object?>{'amount': '999.00'},
      ).hash;
      expect(h1, isNot(h2));
    });
  });

  group('verify 篡改检测', () {
    test('未篡改且前驱正确 → 通过', () {
      final log = buildLog(prevHash: OperationLog.genesisHash);
      expect(log.verify(OperationLog.genesisHash), isTrue);
    });

    test('前驱不匹配 → 失败', () {
      final log = buildLog(prevHash: OperationLog.genesisHash);
      expect(log.verify('a' * 64), isFalse);
    });

    test('明细被改但哈希未重算 → 失败', () {
      final original = buildLog(prevHash: OperationLog.genesisHash);
      final tampered = OperationLog(
        logId: original.logId,
        ledgerId: original.ledgerId,
        operatorId: original.operatorId,
        action: original.action,
        targetType: original.targetType,
        targetId: original.targetId,
        detail: <String, Object?>{'k': '被篡改的值'},
        prevHash: original.prevHash,
        hash: original.hash, // 保留旧哈希
        createdAt: original.createdAt,
      );
      expect(tampered.verify(OperationLog.genesisHash), isFalse);
    });

    test('链式衔接：后一条以前一条哈希为前驱', () {
      final first = buildLog(prevHash: OperationLog.genesisHash, logId: 1);
      final second = buildLog(prevHash: first.hash, logId: 2);
      expect(first.verify(OperationLog.genesisHash), isTrue);
      expect(second.verify(first.hash), isTrue);
      expect(second.verify(OperationLog.genesisHash), isFalse);
    });
  });
}
