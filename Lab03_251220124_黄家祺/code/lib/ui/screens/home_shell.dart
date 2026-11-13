import 'package:material_ui/material_ui.dart';

import '../../domain/ledger.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'audit_screen.dart';
import 'entries_screen.dart';
import 'entry_editor_screen.dart';
import 'ledger_settings_screen.dart';
import 'members_screen.dart';
import 'overview_screen.dart';
import 'review_center_screen.dart';
import 'statistics_screen.dart';

/// 主界面外壳：左侧导航 + 顶部账本/用户栏 + 右侧内容区。
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const _destinations = <NavigationRailDestination>[
    NavigationRailDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard),
      label: Text('总览'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long),
      label: Text('条目'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.fact_check_outlined),
      selectedIcon: Icon(Icons.fact_check),
      label: Text('审批中心'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.pie_chart_outline),
      selectedIcon: Icon(Icons.pie_chart),
      label: Text('统计'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.group_outlined),
      selectedIcon: Icon(Icons.group),
      label: Text('成员'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.history_edu_outlined),
      selectedIcon: Icon(Icons.history_edu),
      label: Text('存档'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: Text('账本设置'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    if (session.currentLedger == null) {
      return const Scaffold(
        body: Column(
          children: [
            _TopBar(),
            Divider(height: 1),
            Expanded(child: _NoLedgerView()),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: session.navIndex,
            onDestinationSelected: session.go,
            destinations: _destinations,
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                const _TopBar(),
                const Divider(height: 1),
                Expanded(child: _body(session.navIndex)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(int index) => switch (index) {
    0 => const OverviewScreen(),
    1 => const EntriesScreen(),
    2 => const ReviewCenterScreen(),
    3 => const StatisticsScreen(),
    4 => const MembersScreen(),
    5 => const AuditScreen(),
    _ => const LedgerSettingsScreen(),
  };
}

/// 顶部栏：账本选择器、状态、新建条目、当前用户与退出。
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final theme = Theme.of(context);
    final ledger = session.currentLedger;
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (ledger != null) ...[
            const Icon(Icons.menu_book_outlined, size: 20),
            const SizedBox(width: 8),
            _LedgerPicker(ledger: ledger),
            const SizedBox(width: 10),
            _LedgerStatusChip(ledger: ledger),
          ] else
            Text('尚未加入任何账本', style: theme.textTheme.titleMedium),
          const Spacer(),
          if (ledger != null)
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const EntryEditorScreen(),
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新建条目'),
            ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.secondaryContainer,
            child: Text(
              session.currentUser!.displayName.characters.first,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                session.currentUser!.displayName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '@${session.currentUser!.username}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '退出登录',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final ok = await confirm(
                context,
                title: '退出登录',
                message: '确定要退出当前账号吗？数据已自动保存。',
              );
              if (ok && context.mounted) {
                Session.of(context).logout();
              }
            },
          ),
        ],
      ),
    );
  }
}

class _LedgerPicker extends StatelessWidget {
  const _LedgerPicker({required this.ledger});

  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final ledgers = session.myLedgers;
    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: ledger.ledgerId,
        borderRadius: BorderRadius.circular(10),
        items: [
          for (final l in ledgers)
            DropdownMenuItem(value: l.ledgerId, child: Text(l.name)),
        ],
        onChanged: (id) {
          if (id == null) {
            return;
          }
          final target = ledgers.firstWhere((l) => l.ledgerId == id);
          session.selectLedger(target);
        },
      ),
    );
  }
}

class _LedgerStatusChip extends StatelessWidget {
  const _LedgerStatusChip({required this.ledger});

  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    final readOnly = ledger.isReadOnly;
    final color = readOnly ? const Color(0xFFEF6C00) : AppTheme.income;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        readOnly ? ledger.status.label : '进行中',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 没有任何账本时的引导页。
class _NoLedgerView extends StatelessWidget {
  const _NoLedgerView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.menu_book_outlined,
                  size: 44,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  '开始你的第一个账本',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '创建一个新账本，或用邀请码加入已有账本。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => showCreateLedgerDialog(context),
                        icon: const Icon(Icons.add),
                        label: const Text('创建账本'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => showJoinLedgerDialog(context),
                        icon: const Icon(Icons.vpn_key_outlined),
                        label: const Text('加入账本'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
