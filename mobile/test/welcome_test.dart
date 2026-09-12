import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:krzene_mobile/welcome.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app() => MaterialApp(
    home: WelcomeGate(builder: (_) => const Scaffold(body: Text('Sign in'))),
  );

  testWidgets('first launch advances, goes back and persists completion', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Krzene'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Make it yours'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Krzene'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getBool(WelcomeGate.completedKey),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('skip persists completion on a small display with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: WelcomeGate(builder: (_) => const Text('Sign in')),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getBool(WelcomeGate.completedKey),
      isTrue,
    );
  });
}
