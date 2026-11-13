import '../domain/domain_exception.dart';
import '../domain/entry.dart';
import '../domain/enums.dart';
import '../domain/ledger.dart';
import '../domain/void_request.dart';
import '../policy/entry_workflow.dart';
import '../policy/permission_policy.dart';
import '../policy/void_approval_policy.dart';
import '../repository/memory_database.dart';
import '../repository/repositories.dart';
import 'audit_log_service.dart';

/// 一次投票后的面板状态，界面直接渲染。
class VotePanel {
  const VotePanel({
    required this.request,
    required this.votes,
    required this.agreeCount,
    required this.disagreeCount,
    required this.result,
    required this.needed,
    required this.progress,
    required this.description,
  });

  /// 申请对象。
  final VoidRequest request;

  /// 已投出的票。
  final List<VoidVote> votes;

  /// 同意票数。
  final int agreeCount;

  /// 反对票数。
  final int disagreeCount;

  /// 当前评估结果。
  final VoteResult result;

  /// 还差几票。
  final int needed;

  /// 进度 0.0~1.0。
  final double progress;

  /// 说明文案。
  final String description;
}

/// 作废投票服务，对应类图中的 `VoidRequestService`（需求 REQ-010）。
class VoidRequestService {
  VoidRequestService({
    required MemoryDatabase db,
    required VoidRequestRepository requests,
    required VoidVoteRepository votes,
    required EntryRepository entries,
    required LedgerRepository ledgers,
    required PermissionPolicy permissions,
    required VoidApprovalPolicy policy,
    required EntryWorkflow workflow,
    required AuditLogService audit,
    DateTime Function()? clock,
  }) : _db = db,
       _requests = requests,
       _votes = votes,
       _entries = entries,
       _ledgers = ledgers,
       _permissions = permissions,
       _policy = policy,
       _workflow = workflow,
       _audit = audit,
       _clock = clock ?? DateTime.now;

  final MemoryDatabase _db;
  final VoidRequestRepository _requests;
  final VoidVoteRepository _votes;
  final EntryRepository _entries;
  final LedgerRepository _ledgers;
  final PermissionPolicy _permissions;
  final VoidApprovalPolicy _policy;
  final EntryWorkflow _workflow;
  final AuditLogService _audit;

  /// 可注入的时钟，单元测试用它模拟超时，不必真的等 72 小时。
  final DateTime Function() _clock;

  /// 发起作废申请。创建时快照当前管理员总数。
  VoidRequest initiate({
    required int entryId,
    required String reason,
    required int adminId,
  }) {
    final entry = _requireEntry(entryId);
    final ledger = _requireLedger(entry.ledgerId);
    if (!_permissions.canInitiateVoid(ledger, adminId)) {
      throw ForbiddenException('只有管理员可以发起作废');
    }
    if (entry.status != EntryStatus.approved) {
      throw IllegalTransitionException(entry.status, EntryStatus.invalid);
    }
    if (reason.trim().isEmpty) {
      throw ValidationException('作废必须说明理由', field: 'reason');
    }
    final alreadyOpen = _requests
        .byEntry(entryId)
        .any((VoidRequest r) => r.isOpen);
    if (alreadyOpen) {
      throw ConflictException('该条目已有进行中的作废申请');
    }
    final snapshot = _permissions.countActiveAdmins(ledger.ledgerId);
    if (snapshot <= 0) {
      throw ConflictException('账本没有有效管理员，无法发起投票');
    }
    final now = _clock();
    final request = VoidRequest(
      requestId: _db.nextId('voidRequest'),
      ledgerId: ledger.ledgerId,
      entryId: entryId,
      initiatorId: adminId,
      reason: reason.trim(),
      adminCountSnapshot: snapshot,
      deadline: now.add(VoidRequest.defaultWindow),
      createdAt: now,
    );
    _requests.save(request);
    _audit.record(
      DomainEvent(
        ledgerId: ledger.ledgerId,
        operatorId: adminId,
        action: 'VOID_REQUEST',
        targetType: 'VoidRequest',
        targetId: request.requestId,
        detail: <String, Object?>{
          'entryId': entryId,
          'reason': reason.trim(),
          'adminCountSnapshot': snapshot,
          'requiredAgree': request.requiredAgreeCount,
        },
      ),
    );
    return request;
  }

  /// 投票。一人一票，重复投票直接拒绝。
  VotePanel vote({
    required int requestId,
    required VoteDecision decision,
    required int adminId,
  }) {
    final request = _requireRequest(requestId);
    final ledger = _requireLedger(request.ledgerId);
    if (!_permissions.canVote(ledger, adminId)) {
      throw ForbiddenException('只有管理员可以投票');
    }
    if (!request.isOpen) {
      throw ConflictException('该申请已结束，不能再投票');
    }
    final now = _clock();
    if (request.isExpiredAt(now)) {
      _expire(request);
      throw ConflictException('投票已超时失效');
    }
    if (_votes.hasVoted(requestId, adminId)) {
      throw ConflictException('你已经投过票，一人一票不可重复');
    }
    _votes.save(
      VoidVote(
        voteId: _db.nextId('voidVote'),
        requestId: requestId,
        adminId: adminId,
        decision: decision,
        votedAt: now,
      ),
    );
    _audit.record(
      DomainEvent(
        ledgerId: request.ledgerId,
        operatorId: adminId,
        action: 'VOID_VOTE',
        targetType: 'VoidRequest',
        targetId: requestId,
        detail: <String, Object?>{'decision': decision.name},
      ),
    );
    return _settle(request);
  }

  /// 计票并推进状态。达到严格多数则把条目置为无效。
  VotePanel _settle(VoidRequest request) {
    final votes = _votes.byRequest(request.requestId);
    final agree = _policy.countAgree(votes);
    final result = _policy.evaluate(request, agree, _clock());
    if (result == VoteResult.passed && request.isOpen) {
      request.markPassed();
      _requests.save(request);
      final entry = _requireEntry(request.entryId);
      _workflow.invalidate(
        entry,
        '作废申请 ${request.requestId} 投票通过（$agree/'
        '${request.adminCountSnapshot}）',
      );
      _entries.save(entry);
      _audit.record(
        DomainEvent(
          ledgerId: request.ledgerId,
          operatorId: request.initiatorId,
          action: 'VOID_PASSED',
          targetType: 'Entry',
          targetId: entry.entryId,
          detail: <String, Object?>{
            'requestId': request.requestId,
            'agree': agree,
            'snapshot': request.adminCountSnapshot,
          },
        ),
      );
    } else if (result == VoteResult.expired && request.isOpen) {
      _expire(request);
    }
    return panel(request.requestId);
  }

  void _expire(VoidRequest request) {
    request.markExpired();
    _requests.save(request);
    _audit.record(
      DomainEvent(
        ledgerId: request.ledgerId,
        operatorId: request.initiatorId,
        action: 'VOID_EXPIRED',
        targetType: 'VoidRequest',
        targetId: request.requestId,
        detail: <String, Object?>{
          'agree': _policy.countAgree(_votes.byRequest(request.requestId)),
          'snapshot': request.adminCountSnapshot,
        },
      ),
    );
  }

  /// 扫描全部进行中的申请，把超时的置为失效。返回处理条数。
  ///
  /// 界面每次进入审批中心时调用一次，等价于设计里的定时任务。
  int expireDueRequests() {
    final now = _clock();
    var count = 0;
    for (final request in _requests.findAllPending()) {
      if (request.isExpiredAt(now)) {
        _expire(request);
        count++;
      }
    }
    return count;
  }

  /// 构造投票面板数据。
  VotePanel panel(int requestId) {
    final request = _requireRequest(requestId);
    final votes = _votes.byRequest(requestId);
    final agree = _policy.countAgree(votes);
    return VotePanel(
      request: request,
      votes: votes,
      agreeCount: agree,
      disagreeCount: _policy.countDisagree(votes),
      result: _policy.evaluate(request, agree, _clock()),
      needed: _policy.votesStillNeeded(request, agree),
      progress: _policy.progress(request, agree),
      description: _policy.describe(request, votes),
    );
  }

  /// 某账本进行中的作废申请。
  List<VoidRequest> pendingOf(int ledgerId) =>
      _requests.findPendingByLedger(ledgerId);

  /// 某条目的作废申请历史。
  List<VoidRequest> historyOf(int entryId) => _requests.byEntry(entryId);

  /// 某管理员是否已对某申请投票。
  bool hasVoted(int requestId, int adminId) =>
      _votes.hasVoted(requestId, adminId);

  Entry _requireEntry(int entryId) {
    final entry = _entries.findById(entryId);
    if (entry == null) {
      throw NotFoundException('条目 $entryId');
    }
    return entry;
  }

  VoidRequest _requireRequest(int requestId) {
    final request = _requests.findById(requestId);
    if (request == null) {
      throw NotFoundException('作废申请 $requestId');
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
