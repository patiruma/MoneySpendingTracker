import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/database.dart';
import 'data/models/transaction_filter.dart';
import 'data/tables.dart';
import 'features/analytics/analytics_screen.dart';
import 'features/entry/entry_screen.dart';
import 'features/export/export_action.dart';
import 'features/history/history_screen.dart';
import 'features/import/import_action.dart';
import 'features/labels/labels_screen.dart';
import 'shared/providers.dart';
import 'theme/theme.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Spending Tracker',
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}

final GoRouter _router = GoRouter(
  initialLocation: '/entry',
  routes: [
    ShellRoute(
      builder: (context, state, child) => _RootShell(child: child),
      routes: [
        GoRoute(
          path: '/entry',
          builder: (context, state) => const EntryScreen(embedded: true),
        ),
        GoRoute(
          path: '/history',
          builder: (context, state) => const HistoryScreen(),
        ),
        GoRoute(
          path: '/analytics',
          builder: (context, state) => const AnalyticsScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/entry/edit',
      builder: (context, state) => EntryScreen(transaction: state.extra as Transaction?),
    ),
    GoRoute(
      path: '/labels/categories',
      builder: (context, state) => const LabelsScreen(kind: LabelKind.category),
    ),
    GoRoute(
      path: '/labels/payment-methods',
      builder: (context, state) => const LabelsScreen(kind: LabelKind.paymentMethod),
    ),
  ],
);

enum _OverflowAction { importCsv, manageCategories, managePaymentMethods }

class _RootShell extends ConsumerWidget {
  const _RootShell({required this.child});

  final Widget child;

  static const _tabs = ['/entry', '/history', '/analytics'];
  static const _titles = ['Add Transaction', 'History', 'Analytics'];

  int _indexForLocation(String location) {
    final index = _tabs.indexWhere((tab) => location.startsWith(tab));
    return index == -1 ? 0 : index;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexForLocation(location);
    // Export has no filter logic of its own (§2.9) — it reads whichever
    // view's filter is live. History and Analytics hold separate filters, so
    // the export button only appears on those tabs and reads the matching one.
    final TransactionFilter? activeFilter = switch (currentIndex) {
      1 => ref.watch(historyFilterProvider),
      2 => ref.watch(analyticsFilterProvider),
      _ => null,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[currentIndex]),
        actions: [
          if (activeFilter != null)
            IconButton(
              tooltip: 'Export CSV',
              icon: const Icon(Icons.ios_share),
              onPressed: () => exportTransactions(context, ref, activeFilter),
            ),
          PopupMenuButton<_OverflowAction>(
            onSelected: (action) {
              switch (action) {
                // Import takes no filter — a filter narrows what leaves the
                // app, but there is nothing to narrow on the way in — so it
                // lives in the global menu rather than beside the per-view
                // export button.
                case _OverflowAction.importCsv:
                  importTransactions(context, ref);
                case _OverflowAction.manageCategories:
                  context.push('/labels/categories');
                case _OverflowAction.managePaymentMethods:
                  context.push('/labels/payment-methods');
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _OverflowAction.importCsv,
                child: Text('Import CSV'),
              ),
              PopupMenuItem(
                value: _OverflowAction.manageCategories,
                child: Text('Manage Categories'),
              ),
              PopupMenuItem(
                value: _OverflowAction.managePaymentMethods,
                child: Text('Manage Payment Methods'),
              ),
            ],
          ),
        ],
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) => context.go(_tabs[index]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.add_circle_outline), label: 'Add'),
          NavigationDestination(icon: Icon(Icons.list), label: 'History'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Analytics'),
        ],
      ),
    );
  }
}
