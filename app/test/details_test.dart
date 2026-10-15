import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humandetect_app/approaches/approach_details.dart';
import 'package:humandetect_app/approaches/registry.dart';
import 'package:humandetect_app/approaches/server/server_check.dart';
import 'package:humandetect_app/screens/approach_detail_screen.dart';
import 'package:humandetect_app/screens/home_screen.dart';

void main() {
  setUp(() => ServerSettings.url = 'http://192.168.1.23:8765');

  test('every tile has a details page', () {
    for (final tile in [...tier1, ...tier2]) {
      final d = approachDetails[tile.id];
      expect(d, isNotNull, reason: 'tile ${tile.id}');
      expect(d!.steps, isNotEmpty);
      expect(d.components, isNotEmpty);
    }
  });

  for (final d in approachDetails.values) {
    testWidgets('details page ${d.id} renders', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ApproachDetailScreen(details: d, onOpen: () {}),
        ),
      );
      expect(find.text('${d.id} · ${d.title}'), findsOneWidget);
      expect(find.text(d.question), findsOneWidget);
      expect(find.text('How it works'), findsOneWidget);
      expect(find.text('Try it'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Code'), 300);
      expect(find.text('Components'), findsNothing); // scrolled past
    });
  }

  testWidgets('the Details button on a tile opens its page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(ping: () async => '06, 07')),
    );
    await tester.tap(find.text('Details').first);
    await tester.pumpAndSettle();
    expect(find.text(approachDetails['01']!.question), findsOneWidget);
  });

  testWidgets('home grid fits a small phone with large system text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 740),
          textScaler: TextScaler.linear(1.3),
        ),
        child: MaterialApp(home: HomeScreen(ping: () async => '06, 07')),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull); // no overflow
    expect(find.text('Details'), findsWidgets);
  });
}
