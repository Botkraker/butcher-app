import 'package:flutter/material.dart';

import 'native.dart';
import 'repo.dart';
import 'screens_main.dart';
import 'screens_more.dart';
import 'sync.dart';
import 'ui.dart';

/// What every screen needs.
class Deps {
  Deps(this.repo, this.native, this.push, this.neon);
  final Repo repo;
  final Native native;

  /// Sends every unsent row now (debug button). Null when all went up.
  final Future<String?> Function() push;
  final Neon neon;
}

/// Passed to each screen: the app, the way back home, and the back button slot.
class Ctx {
  Ctx(this.deps, this.back, this.slot);
  final Deps deps;
  final VoidCallback back;
  final BackSlot slot;
  Repo get repo => deps.repo;
  Native get native => deps.native;
}

class ButcherApp extends StatelessWidget {
  const ButcherApp(this.deps, {super.key});
  final Deps deps;
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'الجزار',
        theme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: Colors.white),
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: Shell(deps),
      );
}

class Shell extends StatefulWidget {
  const Shell(this.deps, {super.key});
  final Deps deps;
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  String screen = 'home';
  final slot = BackSlot();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.deps.repo.seedProducts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the background: try to send what is waiting.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.deps.repo.kick?.call();
  }

  void go(String s) => setState(() {
        slot.handler = null;
        screen = s;
      });

  @override
  Widget build(BuildContext context) {
    final d = widget.deps;
    return PopScope(
      canPop: screen == 'home',
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (slot.handler?.call() ?? false) return;
        go('home');
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: false,
        body: ListenableBuilder(
          listenable: d.repo,
          builder: (context, _) {
            slot.handler = null;
            final c = Ctx(d, () => go('home'), slot);
            final Widget body = switch (screen) {
              'sale' => SaleScreen(c),
              'products' => ProductsScreen(c),
              'history' => HistoryScreen(c),
              'credits' => CreditScreen(c),
              'buy' => PurchaseScreen(c),
              'spend' => SpendingScreen(c),
              'dash' => DashboardScreen(c),
              'debug' => DebugScreen(c),
              _ => HomeScreen(c, go),
            };
            return Padding(padding: const EdgeInsets.all(4), child: body);
          },
        ),
      ),
    );
  }
}
