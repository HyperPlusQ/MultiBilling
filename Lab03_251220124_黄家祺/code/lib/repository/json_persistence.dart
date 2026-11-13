import 'dart:convert';
import 'dart:io';

import '../domain/attachment.dart';
import '../domain/category.dart';
import '../domain/entry.dart';
import '../domain/ledger.dart';
import '../domain/ledger_member.dart';
import '../domain/modification_request.dart';
import '../domain/operation_log.dart';
import '../domain/review_record.dart';
import '../domain/user.dart';
import '../domain/void_request.dart';
import 'memory_database.dart';

/// JSON 文件持久化。
///
/// 把整个 [MemoryDatabase] 序列化成一个 JSON 文件。数据量是团队记账级别
/// （千条量级），全量读写足够，不需要引入嵌入式数据库。
///
/// 写入采用「先写临时文件再原子改名」，避免进程在写一半时被杀掉
/// 导致存档损坏——这一点在记账场景里比性能更重要。
class JsonPersistence {
  JsonPersistence(this.file);

  /// 存档文件路径。
  final File file;

  /// 当前存档格式版本，便于日后迁移。
  static const int schemaVersion = 1;

  /// 从文件载入数据。文件不存在时返回 false，由调用方决定是否播种演示数据。
  bool load(MemoryDatabase db) {
    if (!file.existsSync()) {
      return false;
    }
    final text = file.readAsStringSync();
    if (text.trim().isEmpty) {
      return false;
    }
    final root = jsonDecode(text) as Map<String, Object?>;
    final version = root['schemaVersion'] as int? ?? 0;
    if (version != schemaVersion) {
      throw FormatException('存档版本 $version 与当前 $schemaVersion 不兼容');
    }
    db.clear();
    _readList<User>(root, 'users', User.fromJson, db.users);
    _readList<Ledger>(root, 'ledgers', Ledger.fromJson, db.ledgers);
    _readList<LedgerMember>(root, 'members', LedgerMember.fromJson, db.members);
    _readList<Category>(root, 'categories', Category.fromJson, db.categories);
    _readList<Entry>(root, 'entries', Entry.fromJson, db.entries);
    _readList<Attachment>(
      root,
      'attachments',
      Attachment.fromJson,
      db.attachments,
    );
    _readList<ReviewRecord>(root, 'reviews', ReviewRecord.fromJson, db.reviews);
    _readList<ModificationRequest>(
      root,
      'modifications',
      ModificationRequest.fromJson,
      db.modifications,
    );
    _readList<VoidRequest>(
      root,
      'voidRequests',
      VoidRequest.fromJson,
      db.voidRequests,
    );
    _readList<VoidVote>(root, 'voidVotes', VoidVote.fromJson, db.voidVotes);
    _readList<OperationLog>(root, 'logs', OperationLog.fromJson, db.logs);
    final sequences =
        root['sequences'] as Map<String, Object?>? ?? <String, Object?>{};
    sequences.forEach((String key, Object? value) {
      db.bumpSequence(key, value! as int);
    });
    return true;
  }

  void _readList<T extends Object>(
    Map<String, Object?> root,
    String key,
    T Function(Map<String, Object?>) parse,
    Map<int, T> target,
  ) {
    final raw = root[key] as List<Object?>? ?? const <Object?>[];
    for (final item in raw) {
      final entity = parse(item! as Map<String, Object?>);
      final id = _idOf(entity);
      target[id] = entity;
    }
  }

  int _idOf(Object entity) {
    if (entity is User) return entity.userId;
    if (entity is Ledger) return entity.ledgerId;
    if (entity is LedgerMember) return entity.memberId;
    if (entity is Category) return entity.categoryId;
    if (entity is Entry) return entity.entryId;
    if (entity is Attachment) return entity.attachmentId;
    if (entity is ReviewRecord) return entity.reviewId;
    if (entity is ModificationRequest) return entity.requestId;
    if (entity is VoidRequest) return entity.requestId;
    if (entity is VoidVote) return entity.voteId;
    if (entity is OperationLog) return entity.logId;
    throw ArgumentError('未知实体类型 ${entity.runtimeType}');
  }

  /// 全量落盘。
  void save(MemoryDatabase db) {
    final root = <String, Object?>{
      'schemaVersion': schemaVersion,
      'savedAt': DateTime.now().toIso8601String(),
      'users': db.users.values.map((User e) => e.toJson()).toList(),
      'ledgers': db.ledgers.values.map((Ledger e) => e.toJson()).toList(),
      'members': db.members.values.map((LedgerMember e) => e.toJson()).toList(),
      'categories': db.categories.values
          .map((Category e) => e.toJson())
          .toList(),
      'entries': db.entries.values.map((Entry e) => e.toJson()).toList(),
      'attachments': db.attachments.values
          .map((Attachment e) => e.toJson())
          .toList(),
      'reviews': db.reviews.values.map((ReviewRecord e) => e.toJson()).toList(),
      'modifications': db.modifications.values
          .map((ModificationRequest e) => e.toJson())
          .toList(),
      'voidRequests': db.voidRequests.values
          .map((VoidRequest e) => e.toJson())
          .toList(),
      'voidVotes': db.voidVotes.values.map((VoidVote e) => e.toJson()).toList(),
      'logs': db.logs.values.map((OperationLog e) => e.toJson()).toList(),
      'sequences': <String, int>{
        'user': db.currentId('user'),
        'ledger': db.currentId('ledger'),
        'member': db.currentId('member'),
        'category': db.currentId('category'),
        'entry': db.currentId('entry'),
        'attachment': db.currentId('attachment'),
        'review': db.currentId('review'),
        'modification': db.currentId('modification'),
        'voidRequest': db.currentId('voidRequest'),
        'voidVote': db.currentId('voidVote'),
        'log': db.currentId('log'),
      },
    };
    final parent = file.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    final temp = File('${file.path}.tmp');
    temp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(root),
      flush: true,
    );
    temp.renameSync(file.path);
  }
}
