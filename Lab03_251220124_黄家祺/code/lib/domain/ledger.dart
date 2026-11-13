import 'dart:math';

import 'enums.dart';
import 'local_date.dart';
import 'money.dart';

/// 账本，对应类图中的 `Ledger`，是整个领域的聚合根。
///
/// 成员、类别、条目、存档都挂在某个账本之下；跨账本的数据互不可见。
class Ledger {
  Ledger({
    required this.ledgerId,
    required this.name,
    required this.validFrom,
    required this.validTo,
    required this.ownerId,
    required this.inviteCode,
    Money? amountLimit,
    this.strictRule = const <String, Object?>{},
    this.status = LedgerStatus.active,
  }) : amountLimit = amountLimit ?? Money.zero,
       assert(validTo >= validFrom, '有效期结束不能早于开始');

  /// 从 JSON 还原。
  factory Ledger.fromJson(Map<String, Object?> json) => Ledger(
    ledgerId: json['ledgerId']! as int,
    name: json['name']! as String,
    validFrom: LocalDate.parse(json['validFrom']! as String),
    validTo: LocalDate.parse(json['validTo']! as String),
    ownerId: json['ownerId']! as int,
    inviteCode: json['inviteCode']! as String,
    amountLimit: json['amountLimitCents'] == null
        ? null
        : Money.ofCents(json['amountLimitCents']! as int),
    strictRule: Map<String, Object?>.from(
      (json['strictRule'] ?? <String, Object?>{}) as Map,
    ),
    status: LedgerStatus.values.firstWhere(
      (LedgerStatus value) => value.name == json['status'],
      orElse: () => LedgerStatus.active,
    ),
  );

  /// 生成 8 位邀请码使用的字符集，去掉易混淆的 `0/O/1/I`。
  static const String _inviteAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// 用给定随机源生成 8 位邀请码。
  static String buildInviteCode(Random random) {
    final buffer = StringBuffer();
    for (var i = 0; i < 8; i++) {
      buffer.write(_inviteAlphabet[random.nextInt(_inviteAlphabet.length)]);
    }
    return buffer.toString();
  }

  /// 主键。
  final int ledgerId;

  /// 账本名称。
  String name;

  /// 有效期起始日（含）。
  LocalDate validFrom;

  /// 有效期结束日（含）。
  LocalDate validTo;

  /// 发起者的用户 id，转让时改变。
  int ownerId;

  /// 邀请码，全局唯一。
  String inviteCode;

  /// 单笔金额上限，`Money.zero` 表示不限制。
  Money amountLimit;

  /// 严格审核规则快照，保留可扩展的配置位。
  Map<String, Object?> strictRule;

  /// 账本状态。
  LedgerStatus status;

  /// 是否已经过了有效期。
  bool isExpired(LocalDate today) => today.compareTo(validTo) > 0;

  /// 是否处于只读（过期或归档）状态，只读账本不能新增与审核。
  bool get isReadOnly => status != LedgerStatus.active;

  /// 判断日期是否落在有效期内。
  bool containsDate(LocalDate date) => date.isBetween(validFrom, validTo);

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'ledgerId': ledgerId,
    'name': name,
    'validFrom': validFrom.toIsoString(),
    'validTo': validTo.toIsoString(),
    'ownerId': ownerId,
    'inviteCode': inviteCode,
    'amountLimitCents': amountLimit.cents,
    'strictRule': strictRule,
    'status': status.name,
  };

  @override
  String toString() => 'Ledger($ledgerId, $name)';
}
