import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humandetect_app/approaches/server/server_check.dart';
import 'package:humandetect_app/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget app(Future<String> Function() ping) =>
    MaterialApp(home: HomeScreen(ping: ping));

/// A tall window so the whole home screen is built (the grid is lazy).
void tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 12000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ServerSettings.url = '';
    ServerSettings.token = '';
  });

  group('normalizeAddress', () {
    test('a bare IP gets http and the default port', () {
      expect(normalizeAddress('192.168.1.23'), 'http://192.168.1.23:8765');
      expect(normalizeAddress('  192.168.1.23  '), 'http://192.168.1.23:8765');
    });
    test('explicit port and scheme are kept', () {
      expect(normalizeAddress('192.168.1.23:9000'), 'http://192.168.1.23:9000');
      expect(normalizeAddress('http://10.0.0.5:8765/'), 'http://10.0.0.5:8765');
      expect(normalizeAddress('http://mac.local'), 'http://mac.local:8765');
    });
    test('https without a port stays on 443', () {
      expect(
        normalizeAddress('https://humandetect.example.com'),
        'https://humandetect.example.com',
      );
    });
    test('empty stays empty', () => expect(normalizeAddress('  '), ''));
  });

  test('the address survives an app restart', () async {
    await ServerSettings.save('192.168.1.99', ' secret ');
    ServerSettings.url = '';
    ServerSettings.token = '';
    await ServerSettings.load();
    expect(ServerSettings.url, 'http://192.168.1.99:8765');
    expect(ServerSettings.token, 'secret');
  });

  testWidgets('first launch asks for the Mac address', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(app(() async => '06'));
    await tester.pumpAndSettle();
    expect(find.text('Server on your Mac'), findsOneWidget);
  });

  testWidgets('Cancel keeps the previous address', (tester) async {
    tallScreen(tester);
    ServerSettings.url = 'http://192.168.1.23:8765';
    await tester.pumpWidget(app(() async => '06, 07'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '10.9.9.9');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(ServerSettings.url, 'http://192.168.1.23:8765');
  });

  testWidgets('Save stores a bare IP in full form and rechecks', (
    tester,
  ) async {
    tallScreen(tester);
    ServerSettings.url = 'http://192.168.1.23:8765';
    var pings = 0;
    await tester.pumpWidget(
      app(() async {
        pings++;
        return '06, 07';
      }),
    );
    await tester.pumpAndSettle();
    expect(pings, 1);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '10.1.2.3');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(ServerSettings.url, 'http://10.1.2.3:8765');
    expect(find.text('http://10.1.2.3:8765'), findsOneWidget);
    expect(pings, 2);
  });

  testWidgets('the app bar icon opens the dialog without scrolling', (
    tester,
  ) async {
    tallScreen(tester);
    ServerSettings.url = 'http://192.168.1.23:8765';
    await tester.pumpWidget(app(() async => '06'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.cloud_done));
    await tester.pumpAndSettle();
    expect(find.text('Server on your Mac'), findsOneWidget);
  });

  testWidgets('status bar shows connected and failed states', (tester) async {
    tallScreen(tester);
    ServerSettings.url = 'http://192.168.1.23:8765';
    await tester.pumpWidget(app(() async => '06, 07, 08, 09'));
    await tester.pumpAndSettle();
    expect(find.text('Connected · approaches 06, 07, 08, 09'), findsOneWidget);

    await tester.pumpWidget(Container()); // dispose the first screen
    await tester.pumpWidget(
      app(() async => throw ServerUnreachable('Cannot reach the server')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cannot reach the server'), findsOneWidget);
  });
}
