import 'package:material_ui/material_ui.dart';

import '../../domain/entry.dart';
import '../../domain/enums.dart';
import '../../domain/money.dart';
import '../../repository/repositories.dart';
import '../../service/statistics_service.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'entry_detail_screen.dart';

/// 总览页：关键指标 + 四个板块入口 + 最近条目。
class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final services = session.services;
    final ledgerId = session.ledgerId;
    final userId = session.userId;
    final summary = services.statistics.summary(ledgerId, const EntryQuery());
    final counts = services.entryService.boardCounts(ledgerId, userId);
    final recent = services.entryService
        .search(ledgerId, const EntryQuery(pageSize: 6), userId)
        .items;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '总览',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          StatisticsService.caliberNote,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 720;
            final cards = <Widget>[
              _StatCard(
                label: '已审核收入',
                money: summary.income,
                color: AppTheme.income,
                icon: Icons.trending_up,
              ),
              _StatCard(
                label: '已审核支出',
                money: summary.expense,
                color: AppTheme.expense,
                icon: Icons.trending_down,
              ),
              _StatCard(
                label: '结余',
                money: summary.balance,
                color: summary.balance.cents >= 0
                    ? AppTheme.income
                    : AppTheme.expense,
                icon: Icons.account_balance_outlined,
              ),
              _CountCard(
                label: '参与统计条目',
                value: '${summary.entryCount}',
                sub: '${summary.memberCount} 名成员有已审核条目',
                icon: Icons.receipt_long_outlined,
              ),
            ];
            if (wide) {
              return Row(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    Expanded(child: cards[i]),
                    if (i < cards.length - 1) const SizedBox(width: 14),
                  ],
                ],
              );
            }
            return Column(
              children: [
                for (var i = 0; i < cards.length; i += 2)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        Expanded(child: cards[i]),
                        const SizedBox(width: 14),
                        Expanded(
                          child: i + 1 < cards.length
                              ? cards[i + 1]
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        SectionCard(
          title: '四个板块',
          subtitle: '板块是条目状态的投影，点击进入对应列表',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _BoardTile(
                status: EntryStatus.pending,
                count: counts[EntryStatus.pending] ?? 0,
              ),
              _BoardTile(
                status: EntryStatus.approved,
                count: counts[EntryStatus.approved] ?? 0,
              ),
              _BoardTile(
                status: EntryStatus.rejected,
                count: counts[EntryStatus.rejected] ?? 0,
              ),
              _BoardTile(
                status: EntryStatus.invalid,
                count: counts[EntryStatus.invalid] ?? 0,
              ),
              _BoardTile(
                status: EntryStatus.draft,
                count: counts[EntryStatus.draft] ?? 0,
                labelOverride: '我的草稿',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SectionCard(
          title: '最近条目',
          subtitle: '按发生时间倒序，最多 6 条',
          child: recent.isEmpty
              ? const EmptyHint(
                  icon: Icons.inbox_outlined,
                  text: '还没有条目，点右上角「新建条目」开始记账',
                )
              : Column(
                  children: [
                    for (var i = 0; i < recent.length; i++) ...[
                      _RecentRow(entry: recent[i]),
                      if (i < recent.length - 1) const Divider(),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.money,
    required this.color,
    required this.icon,
  });

  final String label;
  final Money money;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '¥${money.formatted}',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
  });

  final String label;
  final String value;
  final String sub;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardTile extends StatelessWidget {
  const _BoardTile({
    required this.status,
    required this.count,
    this.labelOverride,
  });

  final EntryStatus status;
  final int count;
  final String? labelOverride;

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final color = statusColor(status);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        session.boardFocus = status;
        session.go(1);
      },
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              labelOverride ?? status.label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '$count',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final category = session.services.categories.findById(entry.categoryId);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EntryDetailScreen(entryId: entry.entryId),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: parseHexColor(category?.color),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${category?.name ?? '未分类'} · '
                    '${session.services.auth.displayNameOf(entry.submitterId)} · '
                    '${formatDate(entry.occurredAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            StatusChip(entry.status, dense: true),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: Align(
                alignment: Alignment.centerRight,
                child: MoneyText(
                  entry.amount,
                  direction: entry.direction,
                  showSign: true,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
