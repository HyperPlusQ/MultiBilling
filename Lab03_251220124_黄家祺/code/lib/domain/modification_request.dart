import 'enums.dart';

/// 修改申请，对应类图中的 `ModificationRequest`。
///
/// 已审核条目不允许原地改动：申请通过时旧条目置无效、按 [proposedSnapshot]
/// 生成一条新的待审核条目重新走审核（设计决策 D6）。这样每一次改动
/// 都留下完整历史，而不是覆盖掉原来的数字。
class ModificationRequest {
  ModificationRequest({
    required this.requestId,
    required this.entryId,
    required this.applicantId,
    required this.proposedSnapshot,
    this.proofAttachmentId,
    this.status = RequestStatus.pending,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewComment,
    required this.createdAt,
  });

  /// 从 JSON 还原。
  factory ModificationRequest.fromJson(Map<String, Object?> json) =>
      ModificationRequest(
        requestId: json['requestId']! as int,
        entryId: json['entryId']! as int,
        applicantId: json['applicantId']! as int,
        proposedSnapshot: Map<String, Object?>.from(
          json['proposedSnapshot']! as Map,
        ),
        proofAttachmentId: json['proofAttachmentId'] as int?,
        status: RequestStatus.values.byName(json['status']! as String),
        reviewedBy: json['reviewedBy'] as int?,
        reviewedAt: json['reviewedAt'] == null
            ? null
            : DateTime.parse(json['reviewedAt']! as String),
        reviewComment: json['reviewComment'] as String?,
        createdAt: DateTime.parse(json['createdAt']! as String),
      );

  /// 主键。
  final int requestId;

  /// 申请修改的原条目。
  final int entryId;

  /// 申请人。
  final int applicantId;

  /// 期望改成的字段快照。
  final Map<String, Object?> proposedSnapshot;

  /// 证明材料附件，必填。
  int? proofAttachmentId;

  /// 流转状态。
  RequestStatus status;

  /// 处理人。
  int? reviewedBy;

  /// 处理时间。
  DateTime? reviewedAt;

  /// 处理意见。
  String? reviewComment;

  /// 提交时间。
  final DateTime createdAt;

  /// 是否仍在等待处理。
  bool get isOpen => status.isOpen;

  /// 标记通过。
  void approve(int reviewerId, String comment) {
    status = RequestStatus.approved;
    reviewedBy = reviewerId;
    reviewedAt = DateTime.now();
    reviewComment = comment;
  }

  /// 标记驳回。
  void reject(int reviewerId, String comment) {
    status = RequestStatus.rejected;
    reviewedBy = reviewerId;
    reviewedAt = DateTime.now();
    reviewComment = comment;
  }

  /// 快照中的字段名到界面标签的映射。
  static const Map<String, String> fieldLabels = <String, String>{
    'title': '标题',
    'categoryId': '类别',
    'direction': '方向',
    'amount': '金额',
    'occurredAt': '发生时间',
    'reason': '事由',
  };

  /// 渲染「改了什么」的对比行，界面在审批中心展示。
  List<String> describeChanges() {
    final result = <String>[];
    for (final entry in proposedSnapshot.entries) {
      if (entry.value == null) {
        continue;
      }
      final label = fieldLabels[entry.key] ?? entry.key;
      result.add('$label：${entry.value}');
    }
    return result;
  }

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'requestId': requestId,
    'entryId': entryId,
    'applicantId': applicantId,
    'proposedSnapshot': proposedSnapshot,
    'proofAttachmentId': proofAttachmentId,
    'status': status.name,
    'reviewedBy': reviewedBy,
    'reviewedAt': reviewedAt?.toIso8601String(),
    'reviewComment': reviewComment,
    'createdAt': createdAt.toIso8601String(),
  };

  @override
  String toString() =>
      'ModificationRequest($requestId, entry=$entryId, ${status.label})';
}
