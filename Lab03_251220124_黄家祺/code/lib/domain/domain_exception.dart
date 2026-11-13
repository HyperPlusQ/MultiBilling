import 'enums.dart';

/// 领域异常。界面层依据 [kind] 与 [field] 渲染提示，不直接展示堆栈。
class DomainException implements Exception {
  DomainException(this.kind, this.message, {this.field});

  /// 错误类别。
  final DomainErrorKind kind;

  /// 面向用户的说明文字。
  final String message;

  /// 出错的表单字段名，界面据此高亮输入框。
  final String? field;

  @override
  String toString() => '${kind.label}：$message';
}

/// 权限不足。
class ForbiddenException extends DomainException {
  ForbiddenException(String message)
    : super(DomainErrorKind.forbidden, message);
}

/// 非法状态迁移。
class IllegalTransitionException extends DomainException {
  IllegalTransitionException(EntryStatus from, EntryStatus to)
    : super(
        DomainErrorKind.illegalTransition,
        '不允许从「${from.label}」直接变为「${to.label}」',
      );
}

/// 字段校验失败。
class ValidationException extends DomainException {
  ValidationException(String message, {super.field})
    : super(DomainErrorKind.validation, message);
}

/// 对象不存在。
class NotFoundException extends DomainException {
  NotFoundException(String what) : super(DomainErrorKind.notFound, '$what 不存在');
}

/// 唯一性或并发冲突。
class ConflictException extends DomainException {
  ConflictException(String message, {super.field})
    : super(DomainErrorKind.conflict, message);
}

/// 缺少证明材料附件。
class ProofRequiredException extends DomainException {
  ProofRequiredException(String message)
    : super(DomainErrorKind.proofRequired, message);
}
