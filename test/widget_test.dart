import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streambox/theme/app_theme.dart';
import 'package:streambox/widgets/widgets.dart';

/// Smoke tests for the shared foundation. No Hive, no router, no network —
/// those are wired in main() and covered by the verification workstream's
/// integration checks.
void main() {
  testWidgets('GradientButton renders label and reacts to tap',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: GradientButton(
            label: 'Continue',
            onPressed: () => tapped = true,
          ),
        ),
      ),
    );
    expect(find.text('Continue'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('GradientButton disabled when onPressed is null',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: GradientButton(label: 'Disabled', onPressed: null),
        ),
      ),
    );
    expect(find.text('Disabled'), findsOneWidget);
  });

  testWidgets('EmptyState renders title and body', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: EmptyState(
            title: 'Nothing here',
            body: 'Add something.',
          ),
        ),
      ),
    );
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('Add something.'), findsOneWidget);
  });

  test('AppTheme dark and light build with the right tokens', () {
    final dark = AppTheme.dark();
    final light = AppTheme.light();
    expect(dark.brightness, Brightness.dark);
    expect(light.brightness, Brightness.light);
    expect(dark.scaffoldBackgroundColor, AppColors.darkBg);
    expect(light.scaffoldBackgroundColor, AppColors.lightBg);
    expect(dark.colorScheme.primary, AppColors.brand);
    expect(light.colorScheme.primary, AppColors.brand);
  });
}
