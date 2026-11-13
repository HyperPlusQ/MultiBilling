import 'package:material_ui/material_ui.dart';

import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'session.dart';
import 'theme.dart';

/// 应用根组件。提供会话作用域与主题，并根据登录状态切换登录页/主界面。
class MultiBillingApp extends StatelessWidget {
  const MultiBillingApp({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      session: session,
      child: MaterialApp(
        title: 'MultiBilling 团队共享记账',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    return session.isLoggedIn ? const HomeShell() : const LoginScreen();
  }
}
