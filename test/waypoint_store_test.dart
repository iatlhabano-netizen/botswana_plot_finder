import 'package:flutter_test/flutter_test.dart';
import 'package:botswana_plot_finder/core/models.dart';

void main() {
  test('SavedWaypoint round-trips JSON with Lo fields', () {
    final wp = SavedWaypoint(
      id: 'wp_1',
      label: 'Corner A',
      lat: -24.6543210,
      lng: 25.9087654,
      createdAt: DateTime.utc(2026, 9, 22, 9, 0),
      loY: 12345.678,
      loX: 98765.432,
      zone: 25,
      datum: 'bw_cape',
    );
    final json = wp.toJson();
    expect(json['id'], 'wp_1');
    expect(json['label'], 'Corner A');
    expect(json['lat'], -24.6543210);
    expect(json['lng'], 25.9087654);
    expect(json['loY'], 12345.678);
    expect(json['loX'], 98765.432);
    expect(json['zone'], 25);
    expect(json['datum'], 'bw_cape');

    final back = SavedWaypoint.fromJson(json);
    expect(back.id, wp.id);
    expect(back.label, wp.label);
    expect(back.lat, wp.lat);
    expect(back.lng, wp.lng);
    expect(back.loY, wp.loY);
    expect(back.loX, wp.loX);
    expect(back.zone, wp.zone);
    expect(back.datum, wp.datum);
    expect(back.hasLo, isTrue);
    expect(back.wgs84Copy, contains('25.9087654'));
    expect(back.loCopy, contains('Y 12345.678'));
    expect(back.loCopy, contains('Lo25'));
  });

  test('SavedWaypoint without Lo omits optional fields', () {
    final wp = SavedWaypoint(
      id: 'wp_2',
      label: 'Gate',
      lat: -22.3,
      lng: 24.6,
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final json = wp.toJson();
    expect(json.containsKey('loY'), isFalse);
    expect(json.containsKey('zone'), isFalse);
    final back = SavedWaypoint.fromJson(json);
    expect(back.hasLo, isFalse);
    expect(back.loCopy, isNull);
    expect(back.copyWith(label: 'Gate 2').label, 'Gate 2');
  });

  test('fromJson tolerates missing createdAt', () {
    final back = SavedWaypoint.fromJson({
      'id': 'x',
      'label': 'Y',
      'lat': 1.0,
      'lng': 2.0,
    });
    expect(back.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
  });
}
