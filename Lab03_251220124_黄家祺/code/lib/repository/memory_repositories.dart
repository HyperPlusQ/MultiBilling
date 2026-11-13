import '../domain/attachment.dart';
import '../domain/category.dart';
import '../domain/entry.dart';
import '../domain/enums.dart';
import '../domain/ledger.dart';
import '../domain/ledger_member.dart';
import '../domain/modification_request.dart';
import '../domain/operation_log.dart';
import '../domain/review_record.dart';
import '../domain/user.dart';
import '../domain/void_request.dart';
import 'memory_database.dart';
import 'repositories.dart';

/// 用户仓储的内存实现。
class MemoryUserRepository implements UserRepository {
  MemoryUserRepository(this._db);

  final MemoryDatabase _db;

  @override
  User? findById(int userId) => _db.users[userId];

  @override
  User? findByUsername(String username) {
    for (final user in _db.users.values) {
      if (user.username == username) {
        return user;
      }
    }
    return null;
  }

  @override
  User save(User user) {
    _db.users[user.userId] = user;
    _db.bumpSequence('user', user.userId);
    return user;
  }

  @override
  List<User> all() => _db.users.values.toList();
}

/// 账本仓储的内存实现。
class MemoryLedgerRepository implements LedgerRepository {
  MemoryLedgerRepository(this._db);

  final MemoryDatabase _db;

  @override
  Ledger? findById(int ledgerId) => _db.ledgers[ledgerId];

  @override
  Ledger? findByInviteCode(String code) {
    for (final ledger in _db.ledgers.values) {
      if (ledger.inviteCode == code) {
        return ledger;
      }
    }
    return null;
  }

  @override
  Ledger save(Ledger ledger) {
    _db.ledgers[ledger.ledgerId] = ledger;
    _db.bumpSequence('ledger', ledger.ledgerId);
    return ledger;
  }

  @override
  List<Ledger> all() => _db.ledgers.values.toList();

  @override
  List<LedgerMember> findMembers(int ledgerId) =>
      _db.members.values
          .where((LedgerMember m) => m.ledgerId == ledgerId)
          .toList()
        ..sort((LedgerMember a, LedgerMember b) => a.memberId - b.memberId);

  @override
  LedgerMember? findMember(int ledgerId, int userId) {
    for (final member in _db.members.values) {
      if (member.ledgerId == ledgerId && member.userId == userId) {
        return member;
      }
    }
    return null;
  }

  @override
  LedgerMember saveMember(LedgerMember member) {
    _db.members[member.memberId] = member;
    _db.bumpSequence('member', member.memberId);
    return member;
  }

  @override
  List<int> findLedgerIdsOfUser(int userId) => _db.members.values
      .where((LedgerMember m) => m.userId == userId && !m.hasLeft)
      .map((LedgerMember m) => m.ledgerId)
      .toSet()
      .toList();
}

/// 类别仓储的内存实现。
class MemoryCategoryRepository implements CategoryRepository {
  MemoryCategoryRepository(this._db);

  final MemoryDatabase _db;

  @override
  Category? findById(int categoryId) => _db.categories[categoryId];

  @override
  List<Category> byLedger(int ledgerId) =>
      _db.categories.values
          .where((Category c) => c.ledgerId == ledgerId)
          .toList()
        ..sort((Category a, Category b) {
          final byDirection = a.direction.index - b.direction.index;
          return byDirection != 0 ? byDirection : a.sortNo - b.sortNo;
        });

  @override
  Category save(Category category) {
    _db.categories[category.categoryId] = category;
    _db.bumpSequence('category', category.categoryId);
    return category;
  }
}

/// 条目仓储的内存实现。
class MemoryEntryRepository implements EntryRepository {
  MemoryEntryRepository(this._db);

  final MemoryDatabase _db;

  @override
  Entry? findById(int entryId) => _db.entries[entryId];

  @override
  Entry save(Entry entry) {
    _db.entries[entry.entryId] = entry;
    _db.bumpSequence('entry', entry.entryId);
    return entry;
  }

  @override
  Page<Entry> search(int ledgerId, EntryQuery query) {
    final matched =
        _db.entries.values
            .where((Entry e) => e.ledgerId == ledgerId && query.matches(e))
            .toList()
          ..sort((Entry a, Entry b) {
            final byTime = b.occurredAt.compareTo(a.occurredAt);
            return byTime != 0 ? byTime : b.entryId - a.entryId;
          });
    final start = (query.page - 1) * query.pageSize;
    if (start >= matched.length) {
      return Page<Entry>(
        items: const <Entry>[],
        total: matched.length,
        page: query.page,
        pageSize: query.pageSize,
      );
    }
    final end = start + query.pageSize;
    return Page<Entry>(
      items: matched.sublist(
        start,
        end > matched.length ? matched.length : end,
      ),
      total: matched.length,
      page: query.page,
      pageSize: query.pageSize,
    );
  }

  @override
  List<Entry> byLedger(int ledgerId) =>
      _db.entries.values.where((Entry e) => e.ledgerId == ledgerId).toList();

  @override
  List<Entry> findByFingerprint(int ledgerId, String fingerprint) => _db
      .entries
      .values
      .where(
        (Entry e) =>
            e.ledgerId == ledgerId && e.duplicateFingerprint == fingerprint,
      )
      .toList();

  @override
  int countApprovedByFingerprint(int ledgerId, String fingerprint) =>
      findByFingerprint(
        ledgerId,
        fingerprint,
      ).where((Entry e) => e.status == EntryStatus.approved).length;

  @override
  List<Entry> approvedForStatistics(int ledgerId) => _db.entries.values
      .where(
        (Entry e) => e.ledgerId == ledgerId && e.status == EntryStatus.approved,
      )
      .toList();
}

/// 附件仓储的内存实现。
class MemoryAttachmentRepository implements AttachmentRepository {
  MemoryAttachmentRepository(this._db);

  final MemoryDatabase _db;

  @override
  Attachment? findById(int attachmentId) => _db.attachments[attachmentId];

  @override
  List<Attachment> byEntry(int entryId) =>
      _db.attachments.values
          .where((Attachment a) => a.entryId == entryId)
          .toList()
        ..sort((Attachment a, Attachment b) => a.attachmentId - b.attachmentId);

  @override
  bool hasPurpose(int entryId, AttachmentPurpose purpose) =>
      byEntry(entryId).any((Attachment a) => a.purpose == purpose);

  @override
  Attachment save(Attachment attachment) {
    _db.attachments[attachment.attachmentId] = attachment;
    _db.bumpSequence('attachment', attachment.attachmentId);
    return attachment;
  }
}

/// 审核记录仓储的内存实现。
class MemoryReviewRecordRepository implements ReviewRecordRepository {
  MemoryReviewRecordRepository(this._db);

  final MemoryDatabase _db;

  @override
  List<ReviewRecord> byEntry(int entryId) =>
      _db.reviews.values
          .where((ReviewRecord r) => r.entryId == entryId)
          .toList()
        ..sort((ReviewRecord a, ReviewRecord b) => a.reviewId - b.reviewId);

  @override
  ReviewRecord save(ReviewRecord record) {
    _db.reviews[record.reviewId] = record;
    _db.bumpSequence('review', record.reviewId);
    return record;
  }
}

/// 修改申请仓储的内存实现。
class MemoryModificationRequestRepository
    implements ModificationRequestRepository {
  MemoryModificationRequestRepository(this._db);

  final MemoryDatabase _db;

  @override
  ModificationRequest? findById(int requestId) => _db.modifications[requestId];

  @override
  ModificationRequest? findOpenByEntry(int entryId) {
    for (final request in _db.modifications.values) {
      if (request.entryId == entryId && request.isOpen) {
        return request;
      }
    }
    return null;
  }

  @override
  List<ModificationRequest> byLedger(int ledgerId) {
    final entryIds = _db.entries.values
        .where((Entry e) => e.ledgerId == ledgerId)
        .map((Entry e) => e.entryId)
        .toSet();
    return _db.modifications.values
        .where((ModificationRequest r) => entryIds.contains(r.entryId))
        .toList()
      ..sort(
        (ModificationRequest a, ModificationRequest b) =>
            b.requestId - a.requestId,
      );
  }

  @override
  ModificationRequest save(ModificationRequest request) {
    _db.modifications[request.requestId] = request;
    _db.bumpSequence('modification', request.requestId);
    return request;
  }
}

/// 作废申请仓储的内存实现。
class MemoryVoidRequestRepository implements VoidRequestRepository {
  MemoryVoidRequestRepository(this._db);

  final MemoryDatabase _db;

  @override
  VoidRequest? findById(int requestId) => _db.voidRequests[requestId];

  @override
  List<VoidRequest> findPendingByLedger(int ledgerId) =>
      _db.voidRequests.values
          .where((VoidRequest r) => r.ledgerId == ledgerId && r.isOpen)
          .toList()
        ..sort((VoidRequest a, VoidRequest b) => b.requestId - a.requestId);

  @override
  List<VoidRequest> findAllPending() =>
      _db.voidRequests.values.where((VoidRequest r) => r.isOpen).toList();

  @override
  List<VoidRequest> byEntry(int entryId) =>
      _db.voidRequests.values
          .where((VoidRequest r) => r.entryId == entryId)
          .toList()
        ..sort((VoidRequest a, VoidRequest b) => b.requestId - a.requestId);

  @override
  VoidRequest save(VoidRequest request) {
    _db.voidRequests[request.requestId] = request;
    _db.bumpSequence('voidRequest', request.requestId);
    return request;
  }
}

/// 作废投票仓储的内存实现。
class MemoryVoidVoteRepository implements VoidVoteRepository {
  MemoryVoidVoteRepository(this._db);

  final MemoryDatabase _db;

  @override
  List<VoidVote> byRequest(int requestId) =>
      _db.voidVotes.values
          .where((VoidVote v) => v.requestId == requestId)
          .toList()
        ..sort((VoidVote a, VoidVote b) => a.voteId - b.voteId);

  @override
  bool hasVoted(int requestId, int adminId) => _db.voidVotes.values.any(
    (VoidVote v) => v.requestId == requestId && v.adminId == adminId,
  );

  @override
  VoidVote save(VoidVote vote) {
    _db.voidVotes[vote.voteId] = vote;
    _db.bumpSequence('voidVote', vote.voteId);
    return vote;
  }
}

/// 操作存档仓储的内存实现。
///
/// 只实现 append 与查询，没有 update / delete，对应实验二
/// 「数据库账号仅授予 INSERT/SELECT」的约束在单机版的等价做法。
class MemoryOperationLogRepository implements OperationLogRepository {
  MemoryOperationLogRepository(this._db);

  final MemoryDatabase _db;

  @override
  OperationLog append(OperationLog log) {
    _db.logs[log.logId] = log;
    _db.bumpSequence('log', log.logId);
    return log;
  }

  @override
  String lastHash(int ledgerId) {
    final chain = byLedger(ledgerId);
    if (chain.isEmpty) {
      return OperationLog.genesisHash;
    }
    return chain.last.hash;
  }

  @override
  List<OperationLog> byLedger(int ledgerId) =>
      _db.logs.values.where((OperationLog l) => l.ledgerId == ledgerId).toList()
        ..sort((OperationLog a, OperationLog b) => a.logId - b.logId);
}
