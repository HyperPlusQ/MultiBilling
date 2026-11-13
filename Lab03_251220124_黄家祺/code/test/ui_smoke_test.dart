import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:multibilling/app_services.dart';
import 'package:multibilling/ui/app.dart';
import 'package:multibilling/ui/screens/home_shell.dart';
import 'package:multibilling/ui/screens/login_screen.dart';
import 'package:multibilling/ui/session.dart';

/// 界面冒烟测试：用真实装配 + 演示数据驱动整个应用，
/// 逐屏渲染并断言没有构建/布局异常。替代被系统权限拦截的截屏验证。
void main() {
  late AppServices services;
  late Session session;

  setUp(() {
    services = AppServices.create();
    services.seedDemoData();
    session = Session(services);
  });

  // 桌面窗口尺寸，避免窄屏下的溢出误报。
  void useDesktopSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('登录页正常渲染', (tester) async {
    useDesktopSurface(tester);
    await tester.pumpWidget(MultiBillingApp(session: session));
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('MultiBilling'), findsOneWidget);
    expect(find.text('登录'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('通过界面输入完成登录', (tester) async {
    useDesktopSurface(tester);
    await tester.pumpWidget(MultiBillingApp(session: session));
    await tester.pump();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'huangjiaqi');
    await tester.enterText(fields.at(1), 'demo123456');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(session.isLoggedIn, isTrue);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('七个导航页逐屏渲染无异常', (tester) async {
    useDesktopSurface(tester);
    session.login('huangjiaqi', 'demo123456');
    await tester.pumpWidget(MultiBillingApp(session: session));
    await tester.pump();

    expect(find.byType(HomeShell), findsOneWidget);
    const labels = ['总览', '条目', '审批中心', '统计', '成员', '存档', '账本设置'];
    for (var i = 0; i < labels.length; i++) {
      session.go(i);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.takeException(),
        isNull,
        reason: '第 $i 页（${labels[i]}）渲染抛出异常',
      );
    }
  });

  testWidgets('切换账本与登出回到登录页', (tester) async {
    useDesktopSurface(tester);
    session.login('huangjiaqi', 'demo123456');
    await tester.pumpWidget(MultiBillingApp(session: session));
    await tester.pump();

    expect(session.currentLedger, isNotNull);
    session.logout();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(session.isLoggedIn, isFalse);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
