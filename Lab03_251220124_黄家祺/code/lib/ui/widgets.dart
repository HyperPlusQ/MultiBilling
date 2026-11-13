import 'package:material_ui/material_ui.dart';

import '../domain/domain_exception.dart';
import '../domain/enums.dart';
import '../domain/money.dart';
import 'session.dart';
import 'theme.dart';

/// 执行业务动作的统一包装：成功则落盘刷新并可选提示，失败则把领域异常
/// 翻译成可读SnackBar。界面不直接 try/catch，避免各处提示风格不一。
void guard(BuildContext context, void Function() action, {String? success}) {
  final session = Session.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    action();
    session.touch();
    if (success != null) {
      _snack(messenger, success, error: false);
    }
  } on DomainException catch (e) {
    _snack(messenger, e.message, error: true);
  }
}

/// 异步版本的 [guard]，用于需要 await 的动作（如文件选择）。
Future<void> guardAsync(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  final session = Session.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    session.touch();
    if (success != null) {
      _snack(messenger, success, error: false);
    }
  } on DomainException catch (e) {
    _snack(messenger, e.message, error: true);
  }
}

/// 直接弹一条提示。
void showSnack(BuildContext context, String message, {bool error = false}) {
  _snack(ScaffoldMessenger.of(context), message, error: error);
}

void _snack(
  ScaffoldMessengerState messenger,
  String message, {
  required bool error,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFFB3261E) : null,
        behavior: SnackBarBehavior.floating,
        width: 460,
      ),
    );
}

/// 确认对话框，返回用户是否点了确定。
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String okLabel = '确定',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E))
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(okLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 条目状态标签。
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.dense = false});

  final EntryStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 10,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: dense ? 11 : 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 申请状态标签。
class RequestStatusChip extends StatelessWidget {
  const RequestStatusChip(this.status, {super.key});

  final RequestStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      RequestStatus.pending => const Color(0xFFEF6C00),
      RequestStatus.approved => AppTheme.income,
      RequestStatus.rejected => AppTheme.expense,
      RequestStatus.expired => const Color(0xFF607D8B),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 状态到颜色的固定映射，全局统一。
Color statusColor(EntryStatus status) => switch (status) {
  EntryStatus.draft => const Color(0xFF757575),
  EntryStatus.pending => const Color(0xFFEF6C00),
  EntryStatus.approved => AppTheme.income,
  EntryStatus.rejected => AppTheme.expense,
  EntryStatus.invalid => const Color(0xFF607D8B),
};

/// 收支方向标签。
class DirectionChip extends StatelessWidget {
  const DirectionChip(this.direction, {super.key});

  final EntryDirection direction;

  @override
  Widget build(BuildContext context) {
    final isIncome = direction == EntryDirection.income;
    final color = isIncome ? AppTheme.income : AppTheme.expense;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        direction.label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 金额文本，按方向着色并带符号。
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.money, {
    super.key,
    this.direction,
    this.style,
    this.showSign = false,
  });

  final Money money;
  final EntryDirection? direction;
  final TextStyle? style;
  final bool showSign;

  @override
  Widget build(BuildContext context) {
    final isIncome = direction == EntryDirection.income;
    final color = direction == null
        ? null
        : (isIncome ? AppTheme.income : AppTheme.expense);
    final prefix = showSign ? (isIncome ? '+' : '-') : '';
    return Text(
      '$prefix¥${money.abs().formatted}',
      style: (style ?? const TextStyle()).copyWith(
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// 带标题的内容卡片。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.subtitle,
    this.padding = const EdgeInsets.all(16),
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// 空状态占位。
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 10),
            Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 键值对展示行，详情页用。
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// 把 DateTime 格式化为 `yyyy-MM-dd HH:mm`。
String formatDateTime(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

/// 把 DateTime 格式化为 `yyyy-MM-dd`。
String formatDate(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

/// 把 `#RRGGBB` 解析为 Color，失败时回退灰色。类别配色统一走这里。
Color parseHexColor(String? hex) {
  if (hex == null || hex.length != 7) {
    return const Color(0xFF9E9E9E);
  }
  final value = int.tryParse(hex.substring(1), radix: 16);
  return value == null ? const Color(0xFF9E9E9E) : Color(0xFF000000 | value);
}

/// 通用文本输入对话框，返回用户输入；取消返回 null。
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  bool multiline = false,
  String okLabel = '确定',
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: multiline ? 3 : 1,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: Text(okLabel),
        ),
      ],
    ),
  ).then((value) {
    controller.dispose();
    return value;
  });
}
