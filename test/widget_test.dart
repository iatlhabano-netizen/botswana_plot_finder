import 'package:flutter_test/flutter_test.dart';
import 'package:botswana_plot_finder/main.dart';

void main() {
  testWidgets('Pathfinder hub launches', (WidgetTester tester) async {
    await tester.pumpWidget(const PathfinderApp());
    await tester.pump();
    expect(find.text('Pathfinder'), findsWidgets);
    expect(find.text('Plot Finder'), findsOneWidget);
    expect(find.text('Area Calculator'), findsOneWidget);
  });
}
