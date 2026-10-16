import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orchard_atlas/data/map_services.dart';
import 'package:orchard_atlas/domain/map_search.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('decimal coordinates validate locally and preserve latitude first', () {
    final p = parseMapCoordinates(' 45.123456, -75.123456 ')!;
    expect(p.latitude, 45.123456);
    expect(p.longitude, -75.123456);
    expect(parseMapCoordinates('-90 180')!.latitude, -90);
    expect(parseMapCoordinates('.5, -.25')!.longitude, -.25);
    expect(parseMapCoordinates('123 Orchard Road'), isNull);
    expect(() => parseMapCoordinates('91, 0'), throwsArgumentError);
    expect(() => parseMapCoordinates('0, -181'), throwsArgumentError);
  });

  test(
    'native address results map to domain locations without Firebase',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        DeviceAddressSearchRepository.channel,
        (call) async {
          if (call.method == 'mapsConfigured') return true;
          expect(call.method, 'searchAddress');
          expect(call.arguments, {'query': 'Orchard Road'});
          return [
            {'label': 'Orchard Road', 'latitude': 45, 'longitude': -75.5},
          ];
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          DeviceAddressSearchRepository.channel,
          null,
        ),
      );
      expect(await DeviceAddressSearchRepository.mapsConfigured(), isTrue);
      final results = await DeviceAddressSearchRepository().search(
        'Orchard Road',
      );
      expect(results.single.label, 'Orchard Road');
      expect(results.single.coordinates.latitude, 45);
      expect(results.single.coordinates.longitude, -75.5);
    },
  );

  test(
    'missing map configuration is safe and failed lookup propagates',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        DeviceAddressSearchRepository.channel,
        (_) async => throw PlatformException(code: 'unavailable'),
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          DeviceAddressSearchRepository.channel,
          null,
        ),
      );
      expect(await DeviceAddressSearchRepository.mapsConfigured(), isFalse);
      await expectLater(
        DeviceAddressSearchRepository().search('Orchard Road'),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
