import '../domain/domain_exception.dart';
import '../domain/entry.dart';
import '../domain/enums.dart';
import '../domain/ledger.dart';
import '../domain/modification_request.dart';
import '../domain/money.dart';
import '../domain/review_record.dart';
import '../policy/entry_workflow.dart';
import '../policy/permission_policy.dart';
import '../repository/memory_database.dart';
import '../repository/repositories.dart';
import 'attachment_service.dart';
import 'audit_log_service.dart';

/// 审核服务，对应类图中的 `ReviewService`（需求 REQ-004、REQ-009）。
class ReviewService {
  ReviewService({
    required MemoryDatabase db,
    required EntryRepository entries,
    required LedgerRepository ledgers,
    required ReviewRecordRepository reviews,
    required ModificationRequestRepository modifications,
    required PermissionPolicy permissions,
    required EntryWorkflow workflow,
    required AttachmentService attachments,
    required AuditLogService audit,
  }) : _db = db,
       _entries = entries,
       _ledgers = ledgers,
       _reviews = reviews,
       _modifications = modifications,
       _permissions = permissions,
       _workflow = workflow,
       _attachments = attachments,
       _audit = audit;

  final MemoryDatabase _db;
  final EntryRepository _entries;
  final LedgerRepository _ledgers;
  final ReviewRecordRepository _reviews;
  final ModificationRequestRepository _modifications;
  final PermissionPolicy _permissions;
  final EntryWorkflow _workflow;
  final AttachmentService _attachments;
  final AuditLogService _audit;

  /// 审核意见长度上限。
  static const int maxCommentLength = 300;

  /// 执行审核动作：通过 / 打回 / 要求补充。
  ///
  /// 打回与要求补充必须填写原因，这是需求 REQ-004 的硬约束。
  ReviewRecord review({
    required int entryId,
    required ReviewAction action,
    required String comment,
    required int adminId,
  }) {
    final entry = _requireEntry(entryId);
    final ledger = _requireLedger(entry.ledgerId);
    if (!_permissions.canReview(ledger, adminId)) {
      throw ForbiddenException('只有管理员可以审核，且账本不能处于只读状态');
    }
    final trimmed = comment.trim();
    if (action.requiresComment && trimmed.isEmpty) {
      throw ValidationException('${action.label}必须填写原因', field: 'comment');
    }
    if (trimmed.length > maxCommentLength) {
      throw ValidationException(
        '审核意见不能超过 $maxCommentLength 字',
        field: 'comment',
      );
    }
    _workflow.review(entry, action, adminId);
    _entries.save(entry);
    final record = ReviewRecord(
      reviewId: _db.nextId('review'),
      entryId: entryId,
      reviewerId: adminId,
      action: action,
      comment: trimmed,
      createdAt: DateTime.now(),
    );
    _reviews.save(record);
    _audit.record(
      DomainEvent(
        ledgerId: entry.ledgerId,
        operatorId: adminId,
        action: _auditActionOf(action),
        targetType: 'Entry',
        targetId: entryId,
        detail: <String, Object?>{
          'action': action.name,
          'comment': trimmed,
          'strictReview': entry.strictReview,
        },
      ),
    );
    return record;
  }

  /// 提交已审核条目的修改申请。
  ///
  /// 必须附证明材料；同一条目同时只能有一条进行中的申请（假设 A3）。
  ModificationRequest applyModification({
    required int entryId,
    required int applicantId,
    required Map<String, Object?> proposedSnapshot,
    required int proofAttachmentId,
  }) {
    final entry = _requireEntry(entryId);
    final ledger = _requireLedger(entry.ledgerId);
    if (!_permissions.canView(entry.ledgerId, applicantId)) {
      throw ForbiddenException('你不是该账本成员');
    }
    if (entry.status != EntryStatus.approved) {
      throw IllegalTransitionException(entry.status, EntryStatus.pending);
    }
    if (_modifications.findOpenByEntry(entryId) != null) {
      throw ConflictException('该条目已有一条进行中的修改申请');
    }
    final proof = _attachments.ofEntry(entryId).where((a) => a.isProof);
    if (proof.isEmpty) {
      throw ProofRequiredException('修改已审核条目必须上传证明材料');
    }
    if (proposedSnapshot.values.every((Object? v) => v == null)) {
      throw ValidationException('没有任何字段需要修改');
    }
    final request = ModificationRequest(
      requestId: _db.nextId('modification'),
      entryId: entryId,
      applicantId: applicantId,
      proposedSnapshot: proposedSnapshot,
      proofAttachmentId: proofAttachmentId,
      createdAt: DateTime.now(),
    );
    _modifications.save(request);
    _audit.record(
      DomainEvent(
        ledgerId: ledger.ledgerId,
        operatorId: applicantId,
        action: 'MOD_REQUEST',
        targetType: 'ModificationRequest',
        targetId: request.requestId,
        detail: <String, Object?>{
          'entryId': entryId,
          'changes': request.describeChanges(),
        },
      ),
    );
    return request;
  }

  /// 通过修改申请：旧条目置无效，按快照生成新的待审核条目。
  ///
  /// 这是设计决策 D6 的落地——不原地改数字，保留完整历史。
  Entry approveModification({
    required int requestId,
    required int adminId,
    String comment = '',
  }) {
    final request = _requireRequest(requestId);
    final oldEntry = _requireEntry(request.entryId);
    final ledger = _requireLedger(oldEntry.ledgerId);
    if (!_permissions.canReview(ledger, adminId)) {
      throw ForbiddenException('只有管理员可以处理修改申请');
    }
    if (!request.isOpen) {
      throw ConflictException('该申请已处理完毕');
    }
    request.approve(adminId, comment.trim());
    _modifications.save(request);

    _workflow.invalidate(oldEntry, '修改申请 $requestId 通过，由新条目替代');
    _entries.save(oldEntry);

    final snapshot = request.proposedSnapshot;
    final replacement = Entry(
      entryId: _db.nextId('entry'),
      ledgerId: oldEntry.ledgerId,
      submitterId: request.applicantId,
      categoryId: snapshot['categoryId'] as int? ?? oldEntry.categoryId,
      title: snapshot['title'] as String? ?? oldEntry.title,
      direction: snapshot['direction'] == null
          ? oldEntry.direction
          : EntryDirection.values.byName(snapshot['direction']! as String),
      amount: snapshot['amount'] == null
          ? oldEntry.amount
          : Money.parse(snapshot['amount']! as String),
      occurredAt: snapshot['occurredAt'] == null
          ? oldEntry.occurredAt
          : DateTime.parse(snapshot['occurredAt']! as String),
      reason: snapshot['reason'] as String? ?? oldEntry.reason,
      status: EntryStatus.pending,
      replacesEntryId: oldEntry.entryId,
      createdAt: DateTime.now(),
    );
    _entries.save(replacement);
    _audit.record(
      DomainEvent(
        ledgerId: ledger.ledgerId,
        operatorId: adminId,
        action: 'MOD_APPROVE',
        targetType: 'ModificationRequest',
        targetId: requestId,
        detail: <String, Object?>{
          'oldEntryId': oldEntry.entryId,
          'newEntryId': replacement.entryId,
        },
      ),
    );
    return replacement;
  }

  /// 驳回修改申请，原条目保持已审核不变。
  void rejectModification({
    required int requestId,
    required int adminId,
    required String comment,
  }) {
    final request = _requireRequest(requestId);
    final entry = _requireEntry(request.entryId);
    final ledger = _requireLedger(entry.ledgerId);
    if (!_permissions.canReview(ledger, adminId)) {
      throw ForbiddenException('只有管理员可以处理修改申请');
    }
    if (!request.isOpen) {
      throw ConflictException('该申请已处理完毕');
    }
    if (comment.trim().isEmpty) {
      throw ValidationException('驳回必须填写原因', field: 'comment');
    }
    request.reject(adminId, comment.trim());
    _modifications.save(request);
    _audit.record(
      DomainEvent(
        ledgerId: ledger.ledgerId,
        operatorId: adminId,
        action: 'MOD_REJECT',
        targetType: 'ModificationRequest',
        targetId: requestId,
        detail: <String, Object?>{'comment': comment.trim()},
      ),
    );
  }

  /// 某条目的审核时间线。
  List<ReviewRecord> timeline(int entryId) => _reviews.byEntry(entryId);

  /// 某账本待处理的修改申请。
  List<ModificationRequest> pendingModifications(int ledgerId) => _modifications
      .byLedger(ledgerId)
      .where((ModificationRequest r) => r.isOpen)
      .toList();

  /// 某账本全部修改申请，审批中心的历史区用。
  List<ModificationRequest> allModifications(int ledgerId) =>
      _modifications.byLedger(ledgerId);

  static String _auditActionOf(ReviewAction action) {
    switch (action) {
      case ReviewAction.approve:
        return 'ENTRY_APPROVE';
      case ReviewAction.reject:
        return 'ENTRY_REJECT';
      case ReviewAction.requestSupplement:
        return 'ENTRY_SUPPLEMENT';
    }
  }

  Entry _requireEntry(int entryId) {
    final entry = _entries.findById(entryId);
    if (entry == null) {
      throw NotFoundException('条目 $entryId');
    }
    return entry;
  }

  ModificationRequest _requireRequest(int requestId) {
    final request = _modifications.findById(requestId);
    if (request == null) {
      throw NotFoundException('修改申请 $requestId');
    }
    return request;
  }

  Ledger _requireLedger(int ledgerId) {
    final ledger = _ledgers.findById(ledgerId);
    if (ledger == null) {
      throw NotFoundException('账本 $ledgerId');
    }
    return ledger;
  }
}
