import '../domain/category.dart';
import '../domain/domain_exception.dart';
import '../domain/entry.dart';
import '../domain/enums.dart';
import '../domain/ledger.dart';
import '../domain/local_date.dart';
import '../domain/money.dart';
import '../policy/amount_limit_policy.dart';
import '../policy/duplicate_checker.dart';
import '../policy/entry_workflow.dart';
import '../policy/permission_policy.dart';
import '../repository/memory_database.dart';
import '../repository/repositories.dart';
import 'attachment_service.dart';
import 'audit_log_service.dart';

/// 新建/编辑条目的输入命令。
///
/// 把表单字段收成一个对象，避免服务方法出现七八个位置参数。
class EntryCommand {
  const EntryCommand({
    required this.categoryId,
    required this.title,
    required this.amount,
    required this.occurredAt,
    required this.reason,
  });

  /// 类别 id，方向由类别决定。
  final int categoryId;

  /// 标题。
  final String title;

  /// 金额。
  final Money amount;

  /// 发生时间。
  final DateTime occurredAt;

  /// 事由。
  final String reason;
}

/// 提交前的预检结果，界面在用户点提交前就能展示提示。
class SubmissionPreview {
  const SubmissionPreview({
    required this.duplicateWarning,
    required this.strictReviewWarning,
    required this.requiresProof,
    required this.proofPresent,
  });

  /// 重复条目提示，空串表示无重复。
  final String duplicateWarning;

  /// 超限提示，空串表示未超限。
  final String strictReviewWarning;

  /// 本次提交是否需要证明材料。
  final bool requiresProof;

  /// 是否已经上传了证明材料。
  final bool proofPresent;

  /// 是否可以直接提交。
  bool get canSubmit => !requiresProof || proofPresent;

  /// 阻止提交的原因，可直接提交时为空串。
  String get blockingReason {
    if (requiresProof && !proofPresent) {
      return '需要上传证明材料后才能提交';
    }
    return '';
  }
}

/// 条目服务，对应类图中的 `EntryService`。
///
/// 提交入口严格按固定顺序执行：
/// 权限 → 字段/金额校验 → 重复检测 → 严格审核判定 → 落库 → 存档。
class EntryService {
  EntryService({
    required MemoryDatabase db,
    required EntryRepository entries,
    required CategoryRepository categories,
    required LedgerRepository ledgers,
    required PermissionPolicy permissions,
    required DuplicateChecker duplicates,
    required AmountLimitPolicy amountLimits,
    required EntryWorkflow workflow,
    required AttachmentService attachments,
    required AuditLogService audit,
  }) : _db = db,
       _entries = entries,
       _categories = categories,
       _ledgers = ledgers,
       _permissions = permissions,
       _duplicates = duplicates,
       _amountLimits = amountLimits,
       _workflow = workflow,
       _attachments = attachments,
       _audit = audit;

  final MemoryDatabase _db;
  final EntryRepository _entries;
  final CategoryRepository _categories;
  final LedgerRepository _ledgers;
  final PermissionPolicy _permissions;
  final DuplicateChecker _duplicates;
  final AmountLimitPolicy _amountLimits;
  final EntryWorkflow _workflow;
  final AttachmentService _attachments;
  final AuditLogService _audit;

  /// 新建草稿。草稿只有提交人自己可见。
  Entry createDraft(int ledgerId, EntryCommand cmd, int userId) {
    final ledger = _requireLedger(ledgerId);
    if (!_permissions.canSubmit(ledger, userId)) {
      throw ForbiddenException('你不是该账本有效成员，或账本已只读');
    }
    final category = _requireCategory(ledgerId, cmd.categoryId);
    _assertDateInValidity(ledger, cmd.occurredAt);
    final entry = Entry(
      entryId: _db.nextId('entry'),
      ledgerId: ledgerId,
      submitterId: userId,
      categoryId: category.categoryId,
      title: cmd.title,
      direction: category.direction,
      amount: cmd.amount,
      occurredAt: cmd.occurredAt,
      reason: cmd.reason,
      createdAt: DateTime.now(),
    );
    _entries.save(entry);
    _audit.record(
      DomainEvent(
        ledgerId: ledgerId,
        operatorId: userId,
        action: 'ENTRY_CREATE',
        targetType: 'Entry',
        targetId: entry.entryId,
        detail: <String, Object?>{
          'title': entry.title,
          'amount': entry.amount.asDecimal,
          'direction': entry.direction.name,
        },
      ),
    );
    return entry;
  }

  /// 编辑草稿或被驳回的条目。
  Entry updateDraft(int entryId, EntryCommand cmd, int userId) {
    final entry = requireEntry(entryId);
    if (!_permissions.canEdit(entry, userId)) {
      throw ForbiddenException('只有提交人可以编辑草稿或被驳回的条目');
    }
    final ledger = _requireLedger(entry.ledgerId);
    final category = _requireCategory(entry.ledgerId, cmd.categoryId);
    _assertDateInValidity(ledger, cmd.occurredAt);
    entry.applyEdits(
      categoryId: category.categoryId,
      title: cmd.title,
      direction: category.direction,
      amount: cmd.amount,
      occurredAt: cmd.occurredAt,
      reason: cmd.reason,
    );
    _entries.save(entry);
    _audit.record(
      DomainEvent(
        ledgerId: entry.ledgerId,
        operatorId: userId,
        action: 'ENTRY_UPDATE',
        targetType: 'Entry',
        targetId: entryId,
        detail: <String, Object?>{'version': entry.version},
      ),
    );
    return entry;
  }

  /// 提交前的预检，不改变任何状态。
  SubmissionPreview preview(int entryId, int userId) {
    final entry = requireEntry(entryId);
    final ledger = _requireLedger(entry.ledgerId);
    final needsProof =
        _duplicates.requiresProof(entry) ||
        _amountLimits.requiredProofCount(ledger, entry.amount) > 0;
    return SubmissionPreview(
      duplicateWarning: _duplicates.describe(entry),
      strictReviewWarning: _amountLimits.describe(ledger, entry.amount),
      requiresProof: needsProof,
      proofPresent: _attachments.ofEntry(entryId).any((a) => a.isProof),
    );
  }

  /// 提交条目：草稿 → 待审核，或被驳回 → 待审核。
  Entry submit(int entryId, int userId) {
    final entry = requireEntry(entryId);
    final ledger = _requireLedger(entry.ledgerId);
    if (!_permissions.canSubmit(ledger, userId)) {
      throw ForbiddenException('你不是该账本有效成员，或账本已只读');
    }
    if (entry.submitterId != userId) {
      throw ForbiddenException('只有提交人本人可以提交该条目');
    }
    entry.validateBasics();
    _assertDateInValidity(ledger, entry.occurredAt);

    final duplicateHit = _duplicates.requiresProof(entry);
    final strict = _amountLimits.requiresStrictReview(ledger, entry.amount);
    if (duplicateHit || strict) {
      _attachments.assertProofPresent(entryId);
    }
    entry.strictReview = strict;

    if (entry.status == EntryStatus.draft) {
      _workflow.submit(entry);
    } else if (entry.status == EntryStatus.rejected) {
      _workflow.resubmit(entry);
    } else {
      throw IllegalTransitionException(entry.status, EntryStatus.pending);
    }
    _entries.save(entry);
    _audit.record(
      DomainEvent(
        ledgerId: entry.ledgerId,
        operatorId: userId,
        action: entry.version > 1 && entry.lastReviewerId != null
            ? 'ENTRY_RESUBMIT'
            : 'ENTRY_SUBMIT',
        targetType: 'Entry',
        targetId: entryId,
        detail: <String, Object?>{
          'amount': entry.amount.asDecimal,
          'strictReview': strict,
          'duplicateProof': duplicateHit,
        },
      ),
    );
    return entry;
  }

  /// 五维组合检索。草稿只对提交人自己可见。
  Page<Entry> search(int ledgerId, EntryQuery query, int userId) {
    if (!_permissions.canView(ledgerId, userId)) {
      throw ForbiddenException('你不是该账本成员，不能查看条目');
    }
    return _entries.search(ledgerId, query.copyWith(includeDraftOf: userId));
  }

  /// 取条目，不存在时抛异常。
  Entry requireEntry(int entryId) {
    final entry = _entries.findById(entryId);
    if (entry == null) {
      throw NotFoundException('条目 $entryId');
    }
    return entry;
  }

  /// 某账本四个板块各自的条目数，界面 Tab 上的角标用。
  Map<EntryStatus, int> boardCounts(int ledgerId, int userId) {
    final all = _entries.byLedger(ledgerId);
    final result = <EntryStatus, int>{};
    for (final status in EntryStatus.values) {
      if (status == EntryStatus.draft) {
        result[status] = all
            .where((Entry e) => e.status == status && e.submitterId == userId)
            .length;
      } else {
        result[status] = all.where((Entry e) => e.status == status).length;
      }
    }
    return result;
  }

  void _assertDateInValidity(Ledger ledger, DateTime occurredAt) {
    final date = LocalDate.fromDateTime(occurredAt);
    if (!ledger.containsDate(date)) {
      throw ValidationException(
        '发生时间 ${date.toIsoString()} 不在账本有效期 '
        '${ledger.validFrom.toIsoString()} ~ '
        '${ledger.validTo.toIsoString()} 内',
        field: 'occurredAt',
      );
    }
  }

  Ledger _requireLedger(int ledgerId) {
    final ledger = _ledgers.findById(ledgerId);
    if (ledger == null) {
      throw NotFoundException('账本 $ledgerId');
    }
    return ledger;
  }

  Category _requireCategory(int ledgerId, int categoryId) {
    final category = _categories.findById(categoryId);
    if (category == null || category.ledgerId != ledgerId) {
      throw NotFoundException('类别 $categoryId');
    }
    return category;
  }
}
