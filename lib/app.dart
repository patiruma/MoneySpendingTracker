import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
  initialLocation: '/history',
  routes: [
    ShellRoute(
      builder: (context, state, child) => _RootShell(child: child),
      routes: [
        GoRoute(
          path: '/history',
          builder: (context, state) => const _PlaceholderScreen(title: 'History'),
        ),
        GoRoute(
          path: '/analytics',
          builder: (context, state) => const _PlaceholderScreen(title: 'Analytics'),
        ),
      ],
    ),
    GoRoute(
      path: '/entry',
      builder: (context, state) => const _PlaceholderPage(title: 'Add Transaction'),
    ),
    GoRoute(
      path: '/labels/categories',
      builder: (context, state) => const _PlaceholderPage(title: 'Manage Categories'),
    ),
    GoRoute(
      path: '/labels/payment-methods',
      builder: (context, state) => const _PlaceholderPage(title: 'Manage Payment Methods'),
    ),
    GoRoute(
      path: '/export',
      builder: (context, state) => const _PlaceholderPage(title: 'Export'),
    ),
  ],
);

enum _OverflowAction { manageCategories, managePaymentMethods, export }

class _RootShell extends StatelessWidget {
  const _RootShell({required this.child});

  final Widget child;

  static const _tabs = ['/history', '/analytics'];

  int _indexForLocation(String location) {
    final index = _tabs.indexWhere((tab) => location.startsWith(tab));
    return index == -1 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexForLocation(location);
    final isHistory = currentIndex == 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(isHistory ? 'History' : 'Analytics'),
        actions: [
          PopupMenuButton<_OverflowAction>(
            onSelected: (action) {
              switch (action) {
                case _OverflowAction.manageCategories:
                  context.push('/labels/categories');
                case _OverflowAction.managePaymentMethods:
                  context.push('/labels/payment-methods');
                case _OverflowAction.export:
                  context.push('/export');
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _OverflowAction.manageCategories,
                child: Text('Manage Categories'),
              ),
              PopupMenuItem(
                value: _OverflowAction.managePaymentMethods,
                child: Text('Manage Payment Methods'),
              ),
              PopupMenuItem(
                value: _OverflowAction.export,
                child: Text('Export'),
              ),
            ],
          ),
        ],
      ),
      body: child,
      floatingActionButton: isHistory
          ? FloatingActionButton(
              onPressed: () => context.push('/entry'),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) => context.go(_tabs[index]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list), label: 'History'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Analytics'),
        ],
      ),
    );
  }
}

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(title));
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text(title)),
    );
  }
}
