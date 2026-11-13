import 'dart:convert';

import 'attachment.dart';

/// 操作存档，对应类图中的 `OperationLog`。
///
/// 追加写 + 哈希链：每条记录的 [hash] 由「上一条的 hash + 本条规范化 JSON」
/// 计算得到。任何对历史记录的篡改都会让后续所有 hash 对不上，
/// 因此 [verify] 能检测出中途被改过的记录。
///
/// 实验二设计里靠数据库账号只授予 INSERT/SELECT 权限来保证不可改；
/// 桌面版没有数据库账号体系，改为在仓储层只暴露 append 与查询方法，
/// 不提供 update/delete 入口。
class OperationLog {
  OperationLog({
    required this.logId,
    required this.ledgerId,
    required this.operatorId,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.detail,
    required this.prevHash,
    required this.hash,
    required this.createdAt,
  });

  /// 从 JSON 还原。
  factory OperationLog.fromJson(Map<String, Object?> json) => OperationLog(
    logId: json['logId']! as int,
    ledgerId: json['ledgerId']! as int,
    operatorId: json['operatorId']! as int,
    action: json['action']! as String,
    targetType: json['targetType']! as String,
    targetId: json['targetId']! as int,
    detail: Map<String, Object?>.from(json['detail']! as Map),
    prevHash: json['prevHash']! as String,
    hash: json['hash']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String),
  );

  /// 链首记录使用的前驱哈希。
  static const String genesisHash =
      '0000000000000000000000000000000000000000000000000000000000000000';

  /// 主键。
  final int logId;

  /// 所属账本。
  final int ledgerId;

  /// 操作人。
  final int operatorId;

  /// 动作标识，如 `ENTRY_SUBMIT`。
  final String action;

  /// 目标类型，如 `Entry`。
  final String targetType;

  /// 目标主键。
  final int targetId;

  /// 结构化明细。
  final Map<String, Object?> detail;

  /// 前一条记录的哈希。
  final String prevHash;

  /// 本条记录的哈希。
  final String hash;

  /// 记录时间。
  final DateTime createdAt;

  /// 规范化 JSON：键按字典序排序，保证同一内容在不同进程得到同一串。
  ///
  /// 直接用 `jsonEncode` 会保留插入顺序，Map 的构造顺序一变哈希就变，
  /// 所以这里显式排序。
  static String canonicalJson(Map<String, Object?> detail) {
    final sortedKeys = detail.keys.toList()..sort();
    final buffer = StringBuffer('{');
    for (var i = 0; i < sortedKeys.length; i++) {
      if (i > 0) {
        buffer.write(',');
      }
      final key = sortedKeys[i];
      buffer
        ..write(jsonEncode(key))
        ..write(':')
        ..write(jsonEncode(detail[key]));
    }
    buffer.write('}');
    return buffer.toString();
  }

  /// 计算一条记录的哈希。
  static String computeHash({
    required String prevHash,
    required int ledgerId,
    required int operatorId,
    required String action,
    required String targetType,
    required int targetId,
    required Map<String, Object?> detail,
    required DateTime createdAt,
  }) {
    final payload = canonicalJson(<String, Object?>{
      'ledgerId': ledgerId,
      'operatorId': operatorId,
      'action': action,
      'targetType': targetType,
      'targetId': targetId,
      'detail': canonicalJson(detail),
      'createdAt': createdAt.toIso8601String(),
    });
    return Attachment.digestText('$prevHash|$payload');
  }

  /// 用给定的前驱哈希重新计算并比对，检测本条是否被篡改。
  bool verify(String expectedPrevHash) {
    if (prevHash != expectedPrevHash) {
      return false;
    }
    final recomputed = computeHash(
      prevHash: prevHash,
      ledgerId: ledgerId,
      operatorId: operatorId,
      action: action,
      targetType: targetType,
      targetId: targetId,
      detail: detail,
      createdAt: createdAt,
    );
    return recomputed == hash;
  }

  /// 动作标识到中文说明的映射，界面存档列表用。
  static const Map<String, String> actionLabels = <String, String>{
    'LEDGER_CREATE': '创建账本',
    'LEDGER_JOIN': '加入账本',
    'LEDGER_LEAVE': '退出账本',
    'LEDGER_TRANSFER': '转让发起者',
    'MEMBER_ROLE_CHANGE': '变更成员权限',
    'AMOUNT_LIMIT_CHANGE': '修改金额上限',
    'ENTRY_CREATE': '新建草稿',
    'ENTRY_UPDATE': '编辑草稿',
    'ENTRY_SUBMIT': '提交条目',
    'ENTRY_RESUBMIT': '重新提交',
    'ENTRY_APPROVE': '审核通过',
    'ENTRY_REJECT': '审核打回',
    'ENTRY_SUPPLEMENT': '要求补充',
    'ENTRY_INVALID': '置为无效',
    'MOD_REQUEST': '申请修改',
    'MOD_APPROVE': '修改申请通过',
    'MOD_REJECT': '修改申请驳回',
    'VOID_REQUEST': '发起作废',
    'VOID_VOTE': '作废投票',
    'VOID_PASSED': '作废通过',
    'VOID_EXPIRED': '作废超时',
    'ATTACHMENT_UPLOAD': '上传附件',
  };

  /// 动作的中文说明。
  String get actionLabel => actionLabels[action] ?? action;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'logId': logId,
    'ledgerId': ledgerId,
    'operatorId': operatorId,
    'action': action,
    'targetType': targetType,
    'targetId': targetId,
    'detail': detail,
    'prevHash': prevHash,
    'hash': hash,
    'createdAt': createdAt.toIso8601String(),
  };

  @override
  String toString() => 'OperationLog($logId, $action, ${hash.substring(0, 8)})';
}
