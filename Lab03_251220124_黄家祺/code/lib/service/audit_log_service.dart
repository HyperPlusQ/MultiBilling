import '../domain/operation_log.dart';
import '../repository/memory_database.dart';
import '../repository/repositories.dart';

/// 领域事件。服务层完成业务动作后发出，由存档服务订阅落库。
///
/// 这样新增一种业务动作时不需要改存档代码，只要发事件即可（设计决策 D7）。
class DomainEvent {
  const DomainEvent({
    required this.ledgerId,
    required this.operatorId,
    required this.action,
    required this.targetType,
    required this.targetId,
    this.detail = const <String, Object?>{},
  });

  /// 所属账本。
  final int ledgerId;

  /// 操作人。
  final int operatorId;

  /// 动作标识。
  final String action;

  /// 目标类型。
  final String targetType;

  /// 目标主键。
  final int targetId;

  /// 结构化明细。
  final Map<String, Object?> detail;
}

/// 存档校验结果。
class ChainVerification {
  const ChainVerification({
    required this.valid,
    required this.checkedCount,
    this.brokenAtLogId,
    this.reason,
  });

  /// 整条链是否完好。
  final bool valid;

  /// 校验过的记录数。
  final int checkedCount;

  /// 第一处断裂的记录 id。
  final int? brokenAtLogId;

  /// 断裂原因说明。
  final String? reason;
}

/// 操作存档服务，对应类图中的 `AuditLogService`（需求 REQ-011）。
///
/// 负责把领域事件写成带哈希链的存档记录，并提供整链校验。
class AuditLogService {
  AuditLogService(this._db, this._logs);

  final MemoryDatabase _db;
  final OperationLogRepository _logs;

  /// 记录一个领域事件。
  ///
  /// 取该账本当前链尾哈希作为前驱，计算本条哈希后追加。
  OperationLog record(DomainEvent event) {
    final prevHash = _logs.lastHash(event.ledgerId);
    final createdAt = DateTime.now();
    final hash = OperationLog.computeHash(
      prevHash: prevHash,
      ledgerId: event.ledgerId,
      operatorId: event.operatorId,
      action: event.action,
      targetType: event.targetType,
      targetId: event.targetId,
      detail: event.detail,
      createdAt: createdAt,
    );
    final log = OperationLog(
      logId: _db.nextId('log'),
      ledgerId: event.ledgerId,
      operatorId: event.operatorId,
      action: event.action,
      targetType: event.targetType,
      targetId: event.targetId,
      detail: event.detail,
      prevHash: prevHash,
      hash: hash,
      createdAt: createdAt,
    );
    return _logs.append(log);
  }

  /// 校验某账本的整条哈希链。
  ///
  /// 逐条重算哈希并比对前驱，任何一处被改动都会在这里暴露。
  ChainVerification verifyChain(int ledgerId) {
    final chain = _logs.byLedger(ledgerId);
    var expectedPrev = OperationLog.genesisHash;
    for (final log in chain) {
      if (!log.verify(expectedPrev)) {
        return ChainVerification(
          valid: false,
          checkedCount: chain.length,
          brokenAtLogId: log.logId,
          reason:
              '记录 ${log.logId}（${log.actionLabel}）的哈希与前驱不匹配，'
              '该条或其之前的记录可能被篡改。',
        );
      }
      expectedPrev = log.hash;
    }
    return ChainVerification(valid: true, checkedCount: chain.length);
  }

  /// 某账本的存档列表，界面存档页用。
  List<OperationLog> history(int ledgerId) => _logs.byLedger(ledgerId);

  /// 链尾哈希的短展示形式。
  String shortTailHash(int ledgerId) {
    final tail = _logs.lastHash(ledgerId);
    return tail.length <= 12 ? tail : tail.substring(0, 12);
  }
}
