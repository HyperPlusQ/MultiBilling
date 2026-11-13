import 'enums.dart';
import 'local_date.dart';

/// 作废投票结果。
enum VoteResult {
  /// 仍需继续等待其他管理员投票。
  voting('投票中'),

  /// 已达到严格多数，条目应置为无效。
  passed('已通过'),

  /// 已过截止时间，不再计票。
  expired('已超时');

  const VoteResult(this.label);

  /// 界面展示用的中文名称。
  final String label;
}

/// 作废申请，对应类图中的 `VoidRequest`。
///
/// 判定不看「当前有几个管理员」，而看创建申请那一刻快照下来的
/// [adminCountSnapshot]（设计决策 D5）。否则有人中途退出会让同一批票
/// 得出不同结论，历史无法解释。
class VoidRequest {
  VoidRequest({
    required this.requestId,
    required this.ledgerId,
    required this.entryId,
    required this.initiatorId,
    required this.reason,
    required this.adminCountSnapshot,
    this.status = RequestStatus.pending,
    required this.deadline,
    required this.createdAt,
  });

  /// 从 JSON 还原。
  factory VoidRequest.fromJson(Map<String, Object?> json) => VoidRequest(
    requestId: json['requestId']! as int,
    ledgerId: json['ledgerId']! as int,
    entryId: json['entryId']! as int,
    initiatorId: json['initiatorId']! as int,
    reason: json['reason']! as String,
    adminCountSnapshot: json['adminCountSnapshot']! as int,
    status: RequestStatus.values.byName(json['status']! as String),
    deadline: DateTime.parse(json['deadline']! as String),
    createdAt: DateTime.parse(json['createdAt']! as String),
  );

  /// 默认投票窗口：72 小时（假设 A1）。
  static const Duration defaultWindow = Duration(hours: 72);

  /// 主键。
  final int requestId;

  /// 所属账本，用于超时扫描与存档归集。
  final int ledgerId;

  /// 申请作废的条目。
  final int entryId;

  /// 发起人。
  final int initiatorId;

  /// 作废理由。
  final String reason;

  /// 发起时的管理员总数快照。
  final int adminCountSnapshot;

  /// 流转状态。
  RequestStatus status;

  /// 投票截止时间。
  final DateTime deadline;

  /// 发起时间。
  final DateTime createdAt;

  /// 是否仍在等待投票。
  bool get isOpen => status.isOpen;

  /// 是否已经过了截止时间。
  bool isExpiredAt(DateTime now) => !now.isBefore(deadline);

  /// 距离截止还剩多久，界面用来画进度条。
  Duration remaining(DateTime now) {
    final left = deadline.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// 达到严格多数所需的同意票数。
  ///
  /// 判定式为 `agree * 2 > snapshot`，即「半数以上」而非「半数及以上」。
  /// 快照为 4 时需 3 票，快照为 3 时需 2 票。
  int get requiredAgreeCount => adminCountSnapshot ~/ 2 + 1;

  /// 纯函数形式的通过判定，供策略类与单元测试直接复用。
  static bool isPassed(int agree, int adminSnapshot) =>
      adminSnapshot > 0 && agree * 2 > adminSnapshot;

  /// 按当前票数判断是否通过。
  bool isPassedWith(int agreeCount) => isPassed(agreeCount, adminCountSnapshot);

  /// 标记为已通过。
  void markPassed() {
    status = RequestStatus.approved;
  }

  /// 标记为已驳回（管理员明确否决到不可能再通过时）。
  void markRejected() {
    status = RequestStatus.rejected;
  }

  /// 标记为超时失效。
  void markExpired() {
    status = RequestStatus.expired;
  }

  /// 剩余有效天数，界面文案用。
  int daysLeft(LocalDate today) =>
      today.daysUntil(LocalDate.fromDateTime(deadline));

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'requestId': requestId,
    'ledgerId': ledgerId,
    'entryId': entryId,
    'initiatorId': initiatorId,
    'reason': reason,
    'adminCountSnapshot': adminCountSnapshot,
    'status': status.name,
    'deadline': deadline.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
  };

  @override
  String toString() =>
      'VoidRequest($requestId, entry=$entryId, ${status.label})';
}

/// 作废投票，对应类图中的 `VoidVote`。
///
/// `(requestId, adminId)` 组合唯一，保证一人一票；改票需要先删除再写入，
/// 界面不提供改票入口。
class VoidVote {
  VoidVote({
    required this.voteId,
    required this.requestId,
    required this.adminId,
    required this.decision,
    required this.votedAt,
  });

  /// 从 JSON 还原。
  factory VoidVote.fromJson(Map<String, Object?> json) => VoidVote(
    voteId: json['voteId']! as int,
    requestId: json['requestId']! as int,
    adminId: json['adminId']! as int,
    decision: VoteDecision.values.byName(json['decision']! as String),
    votedAt: DateTime.parse(json['votedAt']! as String),
  );

  /// 主键。
  final int voteId;

  /// 所属申请。
  final int requestId;

  /// 投票管理员。
  final int adminId;

  /// 决定。
  final VoteDecision decision;

  /// 投票时间。
  final DateTime votedAt;

  /// 是否为同意票。
  bool get isAgree => decision == VoteDecision.agree;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'voteId': voteId,
    'requestId': requestId,
    'adminId': adminId,
    'decision': decision.name,
    'votedAt': votedAt.toIso8601String(),
  };

  @override
  String toString() => 'VoidVote($voteId, req=$requestId, ${decision.label})';
}
