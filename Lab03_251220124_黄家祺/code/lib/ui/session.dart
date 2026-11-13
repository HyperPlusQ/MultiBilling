import 'package:flutter/widgets.dart';

import '../app_services.dart';
import '../domain/enums.dart';
import '../domain/ledger.dart';
import '../domain/local_date.dart';
import '../domain/user.dart';

/// 界面层的会话状态。
///
/// 桌面单机版没有 HTTP 会话，登录成功后由本对象持有当前用户与当前账本，
/// 所有服务调用都显式传入 [userId]。权限判定仍发生在服务/策略层，
/// 这里只负责「当前是谁、在看哪个账本、停在哪个导航页」。
class Session extends ChangeNotifier {
  Session(this.services);

  /// 装配好的全部服务。
  final AppServices services;

  /// 当前登录用户，null 表示未登录。
  User? currentUser;

  /// 当前选中的账本。
  Ledger? currentLedger;

  /// 左侧导航当前页索引。
  int navIndex = 0;

  /// 从总览跳转到条目页时希望聚焦的板块；条目页读取后清空。
  EntryStatus? boardFocus;

  /// 是否已登录。
  bool get isLoggedIn => currentUser != null;

  /// 从组件树取当前会话并订阅其变化，等价于 [SessionScope.of]。
  static Session of(BuildContext context) => SessionScope.of(context);

  /// 当前用户 id，未登录时抛状态错误（调用方应先判断 [isLoggedIn]）。
  int get userId => currentUser!.userId;

  /// 当前账本 id。
  int get ledgerId => currentLedger!.ledgerId;

  /// 当前用户是否当前账本的管理员。
  bool get isAdmin =>
      currentLedger != null && services.memberService.isAdmin(ledgerId, userId);

  /// 当前用户是否当前账本的发起者。
  bool get isOwner => currentLedger != null && currentLedger!.ownerId == userId;

  /// 当前用户可见的账本列表。
  List<Ledger> get myLedgers =>
      isLoggedIn ? services.ledgerService.ledgersOfUser(userId) : <Ledger>[];

  /// 登录。成功后自动选中第一个账本（若有）。
  void login(String username, String password) {
    final user = services.auth.login(username, password);
    currentUser = user;
    navIndex = 0;
    final ledgers = services.ledgerService.ledgersOfUser(user.userId);
    currentLedger = ledgers.isEmpty ? null : ledgers.first;
    _refreshExpiry();
    notifyListeners();
  }

  /// 注册并直接登录。
  void register({
    required String username,
    required String password,
    required String displayName,
  }) {
    services.auth.register(
      username: username,
      password: password,
      displayName: displayName,
    );
    login(username, password);
  }

  /// 退出登录，清空会话。
  void logout() {
    services.save();
    currentUser = null;
    currentLedger = null;
    navIndex = 0;
    notifyListeners();
  }

  /// 切换当前账本。
  void selectLedger(Ledger ledger) {
    currentLedger = ledger;
    navIndex = 0;
    _refreshExpiry();
    notifyListeners();
  }

  /// 切换导航页。
  void go(int index) {
    navIndex = index;
    notifyListeners();
  }

  /// 业务动作完成后调用：落盘并通知界面重建。
  void touch() {
    services.save();
    notifyListeners();
  }

  /// 仅通知界面重建，不落盘（用于纯展示状态变化）。
  void refresh() => notifyListeners();

  void _refreshExpiry() {
    final ledger = currentLedger;
    if (ledger == null) {
      return;
    }
    services.ledgerService.refreshExpiry(ledger.ledgerId, LocalDate.today());
  }
}

/// 供 [SessionScope] 向下传递会话，并在会话变化时重建依赖它的子树。
class SessionScope extends InheritedNotifier<Session> {
  const SessionScope({
    super.key,
    required Session session,
    required super.child,
  }) : super(notifier: session);

  /// 取当前会话，并订阅其变化。
  static Session of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SessionScope>();
    assert(scope != null, 'SessionScope 未在组件树上方提供');
    return scope!.notifier!;
  }
}
