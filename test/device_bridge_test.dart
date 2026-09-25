import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:botswana_plot_finder/services/device_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DeviceBridge.resetBeepCooldown();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('pathfinder/device'),
      null,
    );
  });

  test('beep invokes channel and debounces within cooldown', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('pathfinder/device'),
      (call) async {
        calls.add(call);
        return null;
      },
    );

    await DeviceBridge.beep();
    await DeviceBridge.beep(); // within 1600 ms — should no-op
    expect(calls.where((c) => c.method == 'beep').length, 1);

    DeviceBridge.resetBeepCooldown();
    await DeviceBridge.beep();
    expect(calls.where((c) => c.method == 'beep').length, 2);
  });

  test('beepCooldownMs is in the 1.5–2 s band', () {
    expect(DeviceBridge.beepCooldownMs, inInclusiveRange(1500, 2000));
  });
}
