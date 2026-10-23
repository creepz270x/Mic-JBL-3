import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rec_sound_mic/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.example.rec_sound_mic/audio'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getBluetoothStatus') {
          return {
            'isConnected': true,
            'deviceName': 'JBL GO 3',
            'deviceType': 'BLUETOOTH',
          };
        }
        return true;
      },
    );
  });

  testWidgets('JBL Live Mic smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const JblMicApp());
    await tester.pump();
    expect(find.text('JBL'), findsOneWidget);
    expect(find.text('LIVE MIC & RECORDER'), findsOneWidget);
    expect(find.text('Sensitivitas Mic / Volume Penguat'), findsOneWidget);
    expect(find.text('Filter DSP Anti-Melengking'), findsOneWidget);
    expect(find.text('Peredam Suara Jauh & Denging'), findsOneWidget);
  });
}
