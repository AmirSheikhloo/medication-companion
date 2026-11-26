import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/core/ui/app_design.dart';

void main() {
  testWidgets('appearance choices map surfaces and preserve danger and attention',
      (tester) async {
    for (final choice in AppThemeChoice.values) {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(MaterialApp(key: ValueKey('${choice.name}-${brightness.name}'), theme: ThemeData(
          brightness: brightness, extensions: [AppAppearance(choice)]),
          home: Builder(builder: (context) {
            expect(AppPalette.selected(context), choice);
            expect(AppPalette.surface(context, AppColors.background),
              brightness == Brightness.dark ? choice.darkPage : choice.page);
            expect(AppPalette.card(context), brightness == Brightness.dark ? choice.darkCard : Colors.white);
            expect(AppPalette.border(context), brightness == Brightness.dark ? choice.darkBorder : choice.outline);
            expect(AppPalette.card(context), isNot(AppPalette.surface(context, AppColors.background)));
            expect(AppPalette.border(context), isNot(AppPalette.card(context)));
            expect(AppPalette.alertInk(context, true), isNot(AppPalette.alertInk(context, false)));
            expect(AppPalette.alertFill(context, true), isNot(AppPalette.alertFill(context, false)));
            for (final urgent in [true, false]) {
              final fg = AppPalette.alertInk(context, urgent).computeLuminance();
              final bg = AppPalette.alertFill(context, urgent).computeLuminance();
              final contrast = fg > bg ? (fg + .05) / (bg + .05) : (bg + .05) / (fg + .05);
              expect(contrast, greaterThanOrEqualTo(4.5));
            }
            expect(AppPalette.surface(context, AppColors.primary), choice.primary);
            expect(AppPalette.surface(context, AppPalette.attentionSurface),
              brightness == Brightness.dark ? const Color(0xFF223A5D) : AppPalette.attentionSurface);
            return const SizedBox();
          })));
      }
    }
    expect(AppThemeChoice.values.map((c) => c.primary).toSet(), hasLength(4));
    expect(AppThemeChoice.values.map((c) => c.page).toSet(), hasLength(4));
    expect(AppThemeChoice.values.map((c) => c.darkPage).toSet(), hasLength(4));
    expect(AppThemeChoice.values.map((c) => c.darkCard).toSet(), hasLength(4));
    expect(AppThemeChoice.parse('violet'), AppThemeChoice.violet);
    expect(AppThemeChoice.parse('unknown'), AppThemeChoice.cyan);
  });
}
