import 'package:material_ui/material_ui.dart';

import '../../domain/enums.dart';
import '../../domain/void_request.dart';
import '../session.dart';
import '../widgets.dart';

/// 作废申请卡片：展示理由、快照分母、进度、截止时间与投票按钮。
///
/// 详情页与审批中心共用。投票判定（严格多数、超时、一人一票）全部在
/// 服务层完成，这里只负责把 [VotePanel] 渲染出来并收集点击。
class VoidRequestCard extends StatelessWidget {
  const VoidRequestCard({super.key, required this.request});

  final VoidRequest request;

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final services = session.services;
    final panel = services.voidService.panel(request.requestId);
    final theme = Theme.of(context);
    final hasVoted = services.voidService.hasVoted(
      request.requestId,
      session.userId,
    );
    final canVote = session.isAdmin && request.isOpen && !hasVoted;
    final remaining = request.remaining(DateTime.now());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '作废申请 #${request.requestId}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                RequestStatusChip(request.status),
                const Spacer(),
                if (request.isOpen)
                  Text(
                    '剩余 ${remaining.inHours} 小时',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('理由：${request.reason}'),
            const SizedBox(height: 6),
            Text(
              panel.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: panel.progress,
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '截止：${formatDateTime(request.deadline)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (panel.votes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final v in panel.votes)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (v.isAgree
                                    ? const Color(0xFF2E7D32)
                                    : const Color(0xFFC62828))
                                .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${services.auth.displayNameOf(v.adminId)}：'
                        '${v.decision.label}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ],
            if (canVote) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.tonal(
                    onPressed: () => guard(
                      context,
                      () => services.voidService.vote(
                        requestId: request.requestId,
                        decision: VoteDecision.agree,
                        adminId: session.userId,
                      ),
                      success: '已投同意票',
                    ),
                    child: const Text('同意作废'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () => guard(
                      context,
                      () => services.voidService.vote(
                        requestId: request.requestId,
                        decision: VoteDecision.disagree,
                        adminId: session.userId,
                      ),
                      success: '已投反对票',
                    ),
                    child: const Text('不同意'),
                  ),
                ],
              ),
            ] else if (hasVoted && request.isOpen)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '你已投过票，一人一票不可重复。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
