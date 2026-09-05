import 'package:flutter_test/flutter_test.dart';
import 'package:botswana_plot_finder/main.dart';

void main() {
  testWidgets('App launches', (WidgetTester tester) async {
    await tester.pumpWidget(const BotswanaPlotFinderApp());
    expect(find.text('Botswana Plot Finder'), findsOneWidget);
  });
}
