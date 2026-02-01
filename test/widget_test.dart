// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_social_app/main.dart';

void main() {
  testWidgets('App builds without errors', (WidgetTester tester) async {
    // Build the app (use the actual root widget used by this project).
    await tester.pumpWidget(const StarterAppRoot());

    // Verify the app tree contains the root widget.
    expect(find.byType(StarterAppRoot), findsOneWidget);
  });
}
