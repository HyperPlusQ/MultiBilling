import 'dart:io';

import 'domain/entry.dart';
import 'domain/enums.dart';
import 'domain/local_date.dart';
import 'domain/money.dart';
import 'policy/amount_limit_policy.dart';
import 'policy/duplicate_checker.dart';
import 'policy/entry_workflow.dart';
import 'policy/permission_policy.dart';
import 'policy/void_approval_policy.dart';
import 'repository/json_persistence.dart';
import 'repository/memory_database.dart';
import 'repository/memory_repositories.dart';
import 'repository/repositories.dart';
import 'service/attachment_service.dart';
import 'service/audit_log_service.dart';
import 'service/auth_service.dart';
import 'service/entry_service.dart';
import 'service/ledger_service.dart';
import 'service/member_service.dart';
import 'service/review_service.dart';
import 'service/statistics_service.dart';
import 'service/void_request_service.dart';

/// 依赖装配根。
///
/// 所有仓储、策略、服务在这里一次性构造并互相接线，界面层只持有本对象。
/// 这样既避免了服务定位器式的全局单例，也让单元测试可以只装配需要的部分。
class AppServices {
  AppServices._({
    required this.db,
    required this.persistence,
    required this.users,
    required this.ledgers,
    required this.categories,
    required this.entries,
    required this.attachments,
    required this.reviews,
    required this.modifications,
    required this.voidRequests,
    required this.voidVotes,
    required this.logs,
    required this.permissions,
    required this.workflow,
    required this.duplicates,
    required this.amountLimits,
    required this.voidPolicy,
    required this.auth,
    required this.audit,
    required this.ledgerService,
    required this.memberService,
    required this.attachmentService,
    required this.entryService,
    required this.reviewService,
    required this.voidService,
    required this.statistics,
  });

  /// 构造一套完整服务。[dataDir] 为 null 时不落盘，供单元测试使用。
  factory AppServices.create({Directory? dataDir, DateTime Function()? clock}) {
    final db = MemoryDatabase();
    final users = MemoryUserRepository(db);
    final ledgers = MemoryLedgerRepository(db);
    final categories = MemoryCategoryRepository(db);
    final entries = MemoryEntryRepository(db);
    final attachments = MemoryAttachmentRepository(db);
    final reviews = MemoryReviewRecordRepository(db);
    final modifications = MemoryModificationRequestRepository(db);
    final voidRequests = MemoryVoidRequestRepository(db);
    final voidVotes = MemoryVoidVoteRepository(db);
    final logs = MemoryOperationLogRepository(db);

    final permissions = PermissionPolicy(ledgers);
    const workflow = EntryWorkflow();
    final duplicates = DuplicateChecker(entries);
    final amountLimits = AmountLimitPolicy();
    final voidPolicy = VoidApprovalPolicy();

    final auth = AuthService(db, users);
    final audit = AuditLogService(db, logs);
    final ledgerService = LedgerService(
      db: db,
      ledgers: ledgers,
      categories: categories,
      permissions: permissions,
      audit: audit,
    );
    final memberService = MemberService(
      ledgers: ledgers,
      permissions: permissions,
      audit: audit,
      auth: auth,
    );
    final storageRoot = dataDir == null
        ? Directory.systemTemp.createTempSync('mb_attachments')
        : Directory('${dataDir.path}/attachments');
    final attachmentService = AttachmentService(
      db: db,
      attachments: attachments,
      permissions: permissions,
      audit: audit,
      storageRoot: storageRoot,
    );
    final entryService = EntryService(
      db: db,
      entries: entries,
      categories: categories,
      ledgers: ledgers,
      permissions: permissions,
      duplicates: duplicates,
      amountLimits: amountLimits,
      workflow: workflow,
      attachments: attachmentService,
      audit: audit,
    );
    final reviewService = ReviewService(
      db: db,
      entries: entries,
      ledgers: ledgers,
      reviews: reviews,
      modifications: modifications,
      permissions: permissions,
      workflow: workflow,
      attachments: attachmentService,
      audit: audit,
    );
    final voidService = VoidRequestService(
      db: db,
      requests: voidRequests,
      votes: voidVotes,
      entries: entries,
      ledgers: ledgers,
      permissions: permissions,
      policy: voidPolicy,
      workflow: workflow,
      audit: audit,
      clock: clock,
    );
    final statistics = StatisticsService(
      entries: entries,
      categories: categories,
      auth: auth,
    );
    final persistence = dataDir == null
        ? null
        : JsonPersistence(File('${dataDir.path}/multibilling.json'));

    return AppServices._(
      db: db,
      persistence: persistence,
      users: users,
      ledgers: ledgers,
      categories: categories,
      entries: entries,
      attachments: attachments,
      reviews: reviews,
      modifications: modifications,
      voidRequests: voidRequests,
      voidVotes: voidVotes,
      logs: logs,
      permissions: permissions,
      workflow: workflow,
      duplicates: duplicates,
      amountLimits: amountLimits,
      voidPolicy: voidPolicy,
      auth: auth,
      audit: audit,
      ledgerService: ledgerService,
      memberService: memberService,
      attachmentService: attachmentService,
      entryService: entryService,
      reviewService: reviewService,
      voidService: voidService,
      statistics: statistics,
    );
  }

  /// 内存数据库。
  final MemoryDatabase db;

  /// 持久化句柄，测试环境为 null。
  final JsonPersistence? persistence;

  /// 用户仓储。
  final UserRepository users;

  /// 账本仓储。
  final LedgerRepository ledgers;

  /// 类别仓储。
  final CategoryRepository categories;

  /// 条目仓储。
  final EntryRepository entries;

  /// 附件仓储。
  final AttachmentRepository attachments;

  /// 审核记录仓储。
  final ReviewRecordRepository reviews;

  /// 修改申请仓储。
  final ModificationRequestRepository modifications;

  /// 作废申请仓储。
  final VoidRequestRepository voidRequests;

  /// 作废投票仓储。
  final VoidVoteRepository voidVotes;

  /// 存档仓储。
  final OperationLogRepository logs;

  /// 权限策略。
  final PermissionPolicy permissions;

  /// 状态机。
  final EntryWorkflow workflow;

  /// 重复检测。
  final DuplicateChecker duplicates;

  /// 金额限制。
  final AmountLimitPolicy amountLimits;

  /// 投票策略。
  final VoidApprovalPolicy voidPolicy;

  /// 认证服务。
  final AuthService auth;

  /// 存档服务。
  final AuditLogService audit;

  /// 账本服务。
  final LedgerService ledgerService;

  /// 成员服务。
  final MemberService memberService;

  /// 附件服务。
  final AttachmentService attachmentService;

  /// 条目服务。
  final EntryService entryService;

  /// 审核服务。
  final ReviewService reviewService;

  /// 作废服务。
  final VoidRequestService voidService;

  /// 统计服务。
  final StatisticsService statistics;

  /// 从磁盘载入。返回是否成功载入已有数据。
  bool load() => persistence?.load(db) ?? false;

  /// 落盘。测试环境为空操作。
  void save() => persistence?.save(db);

  /// 播种演示数据：三个账号、一个账本、若干条目，覆盖四种状态。
  ///
  /// 只在首次启动（存档不存在）时调用，让界面一打开就有内容可看。
  void seedDemoData() {
    final owner = auth.register(
      username: 'huangjiaqi',
      password: 'demo123456',
      displayName: '黄家祺',
    );
    final admin = auth.register(
      username: 'liadmin',
      password: 'demo123456',
      displayName: '李管理',
    );
    final member = auth.register(
      username: 'wangmember',
      password: 'demo123456',
      displayName: '王成员',
    );
    final today = LocalDate.today();
    final ledger = ledgerService.create(
      name: '软件工程课程小组',
      validFrom: today.plusDays(-60),
      validTo: today.plusDays(120),
      ownerId: owner.userId,
      amountLimit: Money.fromYuan(2000),
    );
    ledgerService.joinByInviteCode(ledger.inviteCode, admin.userId);
    ledgerService.joinByInviteCode(ledger.inviteCode, member.userId);
    memberService.setRole(
      ledgerId: ledger.ledgerId,
      operatorId: owner.userId,
      targetUserId: admin.userId,
      role: MemberRole.admin,
    );

    final expenseCategories = categories
        .byLedger(ledger.ledgerId)
        .where((c) => c.direction == EntryDirection.expense)
        .toList();
    final incomeCategories = categories
        .byLedger(ledger.ledgerId)
        .where((c) => c.direction == EntryDirection.income)
        .toList();

    Entry draft(
      String title,
      int categoryId,
      String yuan,
      int daysAgo,
      int submitter,
    ) {
      return entryService.createDraft(
        ledger.ledgerId,
        EntryCommand(
          categoryId: categoryId,
          title: title,
          amount: Money.fromYuan(double.parse(yuan)),
          occurredAt: DateTime.now().subtract(Duration(days: daysAgo)),
          reason: '演示数据：$title',
        ),
        submitter,
      );
    }

    final approved1 = draft(
      '小组聚餐',
      expenseCategories[0].categoryId,
      '386.50',
      12,
      member.userId,
    );
    entryService.submit(approved1.entryId, member.userId);
    reviewService.review(
      entryId: approved1.entryId,
      action: ReviewAction.approve,
      comment: '票据齐全',
      adminId: admin.userId,
    );

    final approved2 = draft(
      '打印实验报告',
      expenseCategories[2].categoryId,
      '48.00',
      8,
      owner.userId,
    );
    entryService.submit(approved2.entryId, owner.userId);
    reviewService.review(
      entryId: approved2.entryId,
      action: ReviewAction.approve,
      comment: '',
      adminId: owner.userId,
    );

    final income = draft(
      '学院活动补贴',
      incomeCategories[2].categoryId,
      '1500.00',
      20,
      owner.userId,
    );
    entryService.submit(income.entryId, owner.userId);
    reviewService.review(
      entryId: income.entryId,
      action: ReviewAction.approve,
      comment: '已核对到账',
      adminId: admin.userId,
    );

    final pending = draft(
      '打车去答辩现场',
      expenseCategories[1].categoryId,
      '63.00',
      2,
      member.userId,
    );
    entryService.submit(pending.entryId, member.userId);

    final rejected = draft(
      '购买机械键盘',
      expenseCategories[2].categoryId,
      '899.00',
      5,
      member.userId,
    );
    entryService.submit(rejected.entryId, member.userId);
    reviewService.review(
      entryId: rejected.entryId,
      action: ReviewAction.reject,
      comment: '与课程无关，请说明用途或撤回',
      adminId: admin.userId,
    );

    draft(
      '待补充发票的场地费',
      expenseCategories[3].categoryId,
      '260.00',
      1,
      owner.userId,
    );

    save();
  }
}
