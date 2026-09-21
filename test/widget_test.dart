import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:botswana_plot_finder/main.dart';

void main() {
  testWidgets('Pathfinder hub launches', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const PathfinderApp());
    await tester.pumpAndSettle();
    expect(find.text('Pathfinder'), findsWidgets);
    expect(find.text('Find my plot'), findsOneWidget);
    expect(find.text('Walk a line'), findsOneWidget);
    expect(find.text('Calculate area'), findsOneWidget);
  });
}
