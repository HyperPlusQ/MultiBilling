import 'domain_exception.dart';
import 'enums.dart';
import 'local_date.dart';
import 'money.dart';

/// 收支条目，对应类图中的 `Entry`，是审核流转与统计的基本单位。
///
/// 四个业务板块不是四张表，而是 [status] 的投影：`PENDING` 未审核、
/// `APPROVED` 已审核、`REJECTED` 已驳回、`INVALID` 无效。`DRAFT` 仅提交人可见。
class Entry {
  Entry({
    required this.entryId,
    required this.ledgerId,
    required this.submitterId,
    required this.categoryId,
    required this.title,
    required this.direction,
    required this.amount,
    required this.occurredAt,
    required this.reason,
    this.status = EntryStatus.draft,
    this.supplementRequested = false,
    this.strictReview = false,
    this.replacesEntryId,
    this.version = 0,
    required this.createdAt,
    this.updatedAt,
    this.lastReviewerId,
    this.invalidReason,
  }) {
    validateBasics();
  }

  /// 从 JSON 还原。
  factory Entry.fromJson(Map<String, Object?> json) => Entry(
    entryId: json['entryId']! as int,
    ledgerId: json['ledgerId']! as int,
    submitterId: json['submitterId']! as int,
    categoryId: json['categoryId']! as int,
    title: json['title']! as String,
    direction: EntryDirection.values.byName(json['direction']! as String),
    amount: Money.ofCents(json['amountCents']! as int),
    occurredAt: DateTime.parse(json['occurredAt']! as String),
    reason: json['reason']! as String,
    status: EntryStatus.values.byName(json['status']! as String),
    supplementRequested: json['supplementRequested']! as bool,
    strictReview: json['strictReview']! as bool,
    replacesEntryId: json['replacesEntryId'] as int?,
    version: json['version']! as int,
    createdAt: DateTime.parse(json['createdAt']! as String),
    updatedAt: json['updatedAt'] == null
        ? null
        : DateTime.parse(json['updatedAt']! as String),
    lastReviewerId: json['lastReviewerId'] as int?,
    invalidReason: json['invalidReason'] as String?,
  );

  /// 主键。
  final int entryId;

  /// 所属账本。
  final int ledgerId;

  /// 提交人。
  final int submitterId;

  /// 类别。
  int categoryId;

  /// 摘要标题。
  String title;

  /// 收支方向。
  EntryDirection direction;

  /// 金额，恒为正数，方向由 [direction] 决定。
  Money amount;

  /// 业务发生时间。
  DateTime occurredAt;

  /// 事由说明。
  String reason;

  /// 当前状态。
  EntryStatus status;

  /// 管理员是否要求过补充材料。
  bool supplementRequested;

  /// 是否因超过金额上限而需要严格审核。
  bool strictReview;

  /// 若本条目是「修改申请通过后产生的新条目」，指向被作废的旧条目。
  int? replacesEntryId;

  /// 乐观锁版本号，每次修改递增。
  int version;

  /// 创建时间。
  final DateTime createdAt;

  /// 最后修改时间。
  DateTime? updatedAt;

  /// 最近一次做出审核决定的管理员。
  int? lastReviewerId;

  /// 条目被判为无效的原因。
  String? invalidReason;

  /// 标题长度上限。
  static const int maxTitleLength = 60;

  /// 事由长度上限。
  static const int maxReasonLength = 500;

  /// 校验字段级不变量，供构造与编辑共用。
  void validateBasics() {
    if (title.trim().isEmpty) {
      throw ValidationException('标题不能为空', field: 'title');
    }
    if (title.length > maxTitleLength) {
      throw ValidationException('标题不能超过 $maxTitleLength 字', field: 'title');
    }
    if (!amount.isPositive) {
      throw ValidationException('金额必须大于零', field: 'amount');
    }
    if (reason.trim().isEmpty) {
      throw ValidationException('事由不能为空', field: 'reason');
    }
    if (reason.length > maxReasonLength) {
      throw ValidationException('事由不能超过 $maxReasonLength 字', field: 'reason');
    }
  }

  /// 提交人是否可以直接编辑。仅草稿与被驳回条目允许。
  bool isEditableBy(int userId) =>
      submitterId == userId && status.editableBySubmitter;

  /// 是否已进入四个业务板块。
  bool get inBoard => status.inBoard;

  /// 是否参与统计。只有已审核条目计入报表。
  bool get countsInStatistics => status == EntryStatus.approved;

  /// 用于重复检测的指纹：账本 + 方向 + 金额 + 发生时间（精确到分钟）。
  String get duplicateFingerprint {
    final stamp =
        '${occurredAt.year}-${occurredAt.month}-${occurredAt.day}'
        '-${occurredAt.hour}:${occurredAt.minute.toString().padLeft(2, '0')}';
    return '$ledgerId|$direction|$amount|$stamp';
  }

  /// 发生日期。
  LocalDate get occurredDate => LocalDate.fromDateTime(occurredAt);

  /// 草稿提交为待审核。
  void markSubmitted() {
    _requireFrom(EntryStatus.draft, EntryStatus.pending);
    status = EntryStatus.pending;
    touch();
  }

  /// 待审核通过。
  void markApproved(int reviewerId) {
    _requireFrom(EntryStatus.pending, EntryStatus.approved);
    status = EntryStatus.approved;
    lastReviewerId = reviewerId;
    supplementRequested = false;
    touch();
  }

  /// 待审核打回。
  void markRejected(int reviewerId) {
    _requireFrom(EntryStatus.pending, EntryStatus.rejected);
    status = EntryStatus.rejected;
    lastReviewerId = reviewerId;
    touch();
  }

  /// 要求补充材料，条目仍停留在待审核，仅打上标记。
  void markSupplementRequested(int reviewerId) {
    if (status != EntryStatus.pending) {
      throw IllegalTransitionException(status, status);
    }
    supplementRequested = true;
    lastReviewerId = reviewerId;
    touch();
  }

  /// 被判为无效，这是终态。
  void markInvalid(String reasonText) {
    if (status == EntryStatus.invalid) {
      throw IllegalTransitionException(status, EntryStatus.invalid);
    }
    if (reasonText.trim().isEmpty) {
      throw ValidationException('置为无效必须说明原因', field: 'reason');
    }
    status = EntryStatus.invalid;
    invalidReason = reasonText;
    touch();
  }

  /// 打回后重新提交。
  void resubmit() {
    _requireFrom(EntryStatus.rejected, EntryStatus.pending);
    status = EntryStatus.pending;
    touch();
  }

  /// 应用修改申请通过后的字段变更。
  void applyEdits({
    int? categoryId,
    String? title,
    EntryDirection? direction,
    Money? amount,
    DateTime? occurredAt,
    String? reason,
  }) {
    this.categoryId = categoryId ?? this.categoryId;
    this.title = title ?? this.title;
    this.direction = direction ?? this.direction;
    this.amount = amount ?? this.amount;
    this.occurredAt = occurredAt ?? this.occurredAt;
    this.reason = reason ?? this.reason;
    validateBasics();
    touch();
  }

  /// 递增乐观锁版本并刷新时间戳。
  void touch() {
    version += 1;
    updatedAt = DateTime.now();
  }

  void _requireFrom(EntryStatus from, EntryStatus to) {
    if (status != from) {
      throw IllegalTransitionException(status, to);
    }
  }

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'entryId': entryId,
    'ledgerId': ledgerId,
    'submitterId': submitterId,
    'categoryId': categoryId,
    'title': title,
    'direction': direction.name,
    'amountCents': amount.cents,
    'occurredAt': occurredAt.toIso8601String(),
    'reason': reason,
    'status': status.name,
    'supplementRequested': supplementRequested,
    'strictReview': strictReview,
    'replacesEntryId': replacesEntryId,
    'version': version,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'lastReviewerId': lastReviewerId,
    'invalidReason': invalidReason,
  };

  @override
  String toString() => 'Entry($entryId, $title, $amount, ${status.label})';
}
