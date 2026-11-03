import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'ledger_store.dart';
import 'repository.dart';
import 'screens/shell_screen.dart';
import 'theme.dart';

class CashflowApp extends StatefulWidget {
  const CashflowApp({super.key, required this.repository});

  final LedgerRepository repository;

  @override
  State<CashflowApp> createState() => _CashflowAppState();
}

class _CashflowAppState extends State<CashflowApp> {
  late final LedgerStore store = LedgerStore(widget.repository);

  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LedgerScope(
      store: store,
      child: MaterialApp(
        title: '记账',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        themeMode: ThemeMode.light,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const ShellScreen(),
      ),
    );
  }
}

class LedgerScope extends InheritedNotifier<LedgerStore> {
  const LedgerScope({
    super.key,
    required LedgerStore store,
    required super.child,
  }) : super(notifier: store);

  static LedgerStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LedgerScope>();
    assert(scope != null, 'LedgerScope 未找到');
    return scope!.notifier!;
  }
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text('账本无法打开\n$message', textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}
