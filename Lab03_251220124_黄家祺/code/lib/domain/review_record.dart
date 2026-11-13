import 'enums.dart';

/// 审核记录，对应类图中的 `ReviewRecord`。
///
/// 每次管理员动作都留下一条不可修改的记录，条目详情右侧的审核时间线
/// 直接由这些记录渲染。
class ReviewRecord {
  ReviewRecord({
    required this.reviewId,
    required this.entryId,
    required this.reviewerId,
    required this.action,
    required this.comment,
    required this.createdAt,
  });

  /// 从 JSON 还原。
  factory ReviewRecord.fromJson(Map<String, Object?> json) => ReviewRecord(
    reviewId: json['reviewId']! as int,
    entryId: json['entryId']! as int,
    reviewerId: json['reviewerId']! as int,
    action: ReviewAction.values.byName(json['action']! as String),
    comment: json['comment']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String),
  );

  /// 主键。
  final int reviewId;

  /// 被审核的条目。
  final int entryId;

  /// 审核人。
  final int reviewerId;

  /// 动作。
  final ReviewAction action;

  /// 意见；打回与要求补充时必填。
  final String comment;

  /// 发生时间。
  final DateTime createdAt;

  /// 动作对应的颜色，界面用来画时间线节点。
  String get tone {
    switch (action) {
      case ReviewAction.approve:
        return '#16A34A';
      case ReviewAction.reject:
        return '#DC2626';
      case ReviewAction.requestSupplement:
        return '#D97706';
    }
  }

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'reviewId': reviewId,
    'entryId': entryId,
    'reviewerId': reviewerId,
    'action': action.name,
    'comment': comment,
    'createdAt': createdAt.toIso8601String(),
  };

  @override
  String toString() => 'ReviewRecord($reviewId, ${action.label})';
}
