import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/enums.dart';
import '../../service/member_service.dart';
import '../session.dart';
import '../widgets.dart';

/// 成员与权限页：成员列表、邀请码、任免管理员、转让发起者、退出账本。
class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final services = session.services;
    final ledger = session.currentLedger!;
    final members = services.memberService.memberViews(ledger.ledgerId);
    final adminCount = services.memberService.adminCount(ledger.ledgerId);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '成员与权限',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '当前有效管理员 $adminCount 人 · 身份与权限正交：发起者恒为管理员',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '邀请码',
          subtitle: '把邀请码发给同学，对方在「加入账本」中输入即可加入',
          trailing: OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: ledger.inviteCode));
              showSnack(context, '邀请码已复制');
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('复制'),
          ),
          child: SelectableText(
            ledger.inviteCode,
            style: theme.textTheme.headlineSmall?.copyWith(
              letterSpacing: 4,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 18),
        SectionCard(
          title: '成员列表',
          child: Column(
            children: [
              for (var i = 0; i < members.length; i++) ...[
                _MemberRow(view: members[i]),
                if (i < members.length - 1) const Divider(),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (services.permissions.canLeave(ledger, session.userId))
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _leave(context),
              icon: const Icon(Icons.exit_to_app, size: 18),
              label: const Text('退出账本'),
            ),
          ),
      ],
    );
  }

  Future<void> _leave(BuildContext context) async {
    final session = Session.of(context);
    final ok = await confirm(
      context,
      title: '退出账本',
      message: '退出后将不能再查看该账本数据，历史条目仍保留你的署名。确定退出？',
      danger: true,
    );
    if (!ok || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      session.services.ledgerService.leave(session.ledgerId, session.userId);
      final remaining = session.myLedgers;
      session.currentLedger = remaining.isEmpty ? null : remaining.first;
      session.touch();
      messenger.showSnackBar(const SnackBar(content: Text('已退出账本')));
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.view});

  final MemberView view;

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final services = session.services;
    final ledger = session.currentLedger!;
    final theme = Theme.of(context);
    final member = view.member;
    final canManage = services.permissions.canManageAdmin(
      ledger,
      session.userId,
      member,
    );
    final canTransfer = services.permissions.canTransferOwner(
      ledger,
      session.userId,
      member,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: member.isOwner
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            child: Text(
              view.displayName.characters.first,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      view.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    _Badge(text: view.badge, owner: member.isOwner),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '@${view.username} · 加入于 ${formatDate(member.joinedAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (canManage)
            TextButton(
              onPressed: () => guard(
                context,
                () => services.memberService.setRole(
                  ledgerId: ledger.ledgerId,
                  operatorId: session.userId,
                  targetUserId: member.userId,
                  role: member.role == MemberRole.admin
                      ? MemberRole.member
                      : MemberRole.admin,
                ),
                success: '权限已更新',
              ),
              child: Text(member.role == MemberRole.admin ? '取消管理员' : '设为管理员'),
            ),
          if (canTransfer)
            TextButton(
              onPressed: () => _transfer(context, view),
              child: const Text('转让发起者'),
            ),
        ],
      ),
    );
  }

  Future<void> _transfer(BuildContext context, MemberView view) async {
    final session = Session.of(context);
    final ok = await confirm(
      context,
      title: '转让发起者',
      message:
          '确定把发起者转让给「${view.displayName}」？'
          '你将降为参与者但保留管理员权限。',
      danger: true,
    );
    if (!ok || !context.mounted) {
      return;
    }
    guard(
      context,
      () => session.services.ledgerService.transferOwnership(
        session.ledgerId,
        session.userId,
        view.member.userId,
      ),
      success: '已转让发起者',
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.owner});

  final String text;
  final bool owner;

  @override
  Widget build(BuildContext context) {
    final color = owner
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
