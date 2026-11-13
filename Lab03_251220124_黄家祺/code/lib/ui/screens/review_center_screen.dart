import 'package:material_ui/material_ui.dart';

import '../../domain/entry.dart';
import '../../domain/enums.dart';
import '../../domain/modification_request.dart';
import '../../domain/void_request.dart';
import '../../repository/repositories.dart';
import '../session.dart';
import '../widgets.dart';
import 'entry_detail_screen.dart';
import 'void_widgets.dart';

/// 审批中心：待审核条目、修改申请、作废投票三个页签。
///
/// 进入时先扫描一次超时的作废申请（等价于设计里的定时任务）。
/// 非管理员也能看到列表，但操作按钮只对管理员渲染。
class ReviewCenterScreen extends StatelessWidget {
  const ReviewCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final services = session.services;
    services.voidService.expireDueRequests();
    final ledgerId = session.ledgerId;
    final pending = services.entryService
        .search(
          ledgerId,
          const EntryQuery(status: EntryStatus.pending, pageSize: 200),
          session.userId,
        )
        .items;
    final mods = services.reviewService.pendingModifications(ledgerId);
    final voids = services.voidService.pendingOf(ledgerId);

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Text(
                  '审批中心',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 12),
                if (!session.isAdmin)
                  Text(
                    '（你不是管理员，仅可查看）',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          TabBar(
            tabs: [
              Tab(text: '待审核 (${pending.length})'),
              Tab(text: '修改申请 (${mods.length})'),
              Tab(text: '作废投票 (${voids.length})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _PendingList(entries: pending),
                _ModificationList(requests: mods),
                _VoidList(requests: voids),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingList extends StatelessWidget {
  const _PendingList({required this.entries});

  final List<Entry> entries;

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final services = session.services;
    if (entries.isEmpty) {
      return const EmptyHint(icon: Icons.task_alt, text: '没有待审核的条目');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final entry = entries[i];
        final category = services.categories.findById(entry.categoryId);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    MoneyText(
                      entry.amount,
                      direction: entry.direction,
                      showSign: true,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${category?.name ?? ''} · '
                  '${services.auth.displayNameOf(entry.submitterId)} · '
                  '${formatDate(entry.occurredAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (entry.strictReview || entry.supplementRequested)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      [
                        if (entry.strictReview) '超过金额上限，需严格审核',
                        if (entry.supplementRequested) '已要求补充材料',
                      ].join(' · '),
                      style: const TextStyle(
                        color: Color(0xFFEF6C00),
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              EntryDetailScreen(entryId: entry.entryId),
                        ),
                      ),
                      child: const Text('查看详情'),
                    ),
                    if (session.isAdmin) ...[
                      FilledButton.tonal(
                        onPressed: () => guard(
                          context,
                          () => services.reviewService.review(
                            entryId: entry.entryId,
                            action: ReviewAction.approve,
                            comment: '',
                            adminId: session.userId,
                          ),
                          success: '已通过',
                        ),
                        child: const Text('通过'),
                      ),
                      OutlinedButton(
                        onPressed: () => _reject(context, entry),
                        child: const Text('打回'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _reject(BuildContext context, Entry entry) async {
    final session = Session.of(context);
    final comment = await promptText(
      context,
      title: '打回条目',
      label: '原因（必填）',
      multiline: true,
    );
    if (comment == null || !context.mounted) {
      return;
    }
    guard(
      context,
      () => session.services.reviewService.review(
        entryId: entry.entryId,
        action: ReviewAction.reject,
        comment: comment,
        adminId: session.userId,
      ),
      success: '已打回',
    );
  }
}

class _ModificationList extends StatelessWidget {
  const _ModificationList({required this.requests});

  final List<ModificationRequest> requests;

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final services = session.services;
    if (requests.isEmpty) {
      return const EmptyHint(icon: Icons.edit_note, text: '没有待处理的修改申请');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: requests.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final req = requests[i];
        final entry = services.entryService.requireEntry(req.entryId);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '修改「${entry.title}」',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    RequestStatusChip(req.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '申请人：${services.auth.displayNameOf(req.applicantId)} · '
                  '${formatDateTime(req.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final line in req.describeChanges())
                  Text(
                    '· $line',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              EntryDetailScreen(entryId: entry.entryId),
                        ),
                      ),
                      child: const Text('查看原条目'),
                    ),
                    if (session.isAdmin) ...[
                      FilledButton.tonal(
                        onPressed: () => guard(
                          context,
                          () => services.reviewService.approveModification(
                            requestId: req.requestId,
                            adminId: session.userId,
                          ),
                          success: '已通过：原条目置无效，新条目进入待审核',
                        ),
                        child: const Text('通过'),
                      ),
                      OutlinedButton(
                        onPressed: () => _reject(context, req),
                        child: const Text('驳回'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _reject(BuildContext context, ModificationRequest req) async {
    final session = Session.of(context);
    final comment = await promptText(
      context,
      title: '驳回修改申请',
      label: '原因（必填）',
      multiline: true,
    );
    if (comment == null || !context.mounted) {
      return;
    }
    guard(
      context,
      () => session.services.reviewService.rejectModification(
        requestId: req.requestId,
        adminId: session.userId,
        comment: comment,
      ),
      success: '已驳回',
    );
  }
}

class _VoidList extends StatelessWidget {
  const _VoidList({required this.requests});

  final List<VoidRequest> requests;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const EmptyHint(icon: Icons.how_to_vote, text: '没有进行中的作废投票');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: requests.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => VoidRequestCard(request: requests[i]),
    );
  }
}
