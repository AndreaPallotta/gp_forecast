import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gp_forecast/main.dart';

void main() {
  testWidgets('App compiles and loads HomePage', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MyApp(),
      ),
    );

    // Verify GPForecast logo text is found
    expect(find.text('FORECAST'), findsOneWidget);
  });
}
