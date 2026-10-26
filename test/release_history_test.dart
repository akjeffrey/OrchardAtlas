import 'package:flutter_test/flutter_test.dart';
import 'package:orchard_atlas/domain/release_history.dart';

void main() {
  test('history uses the installed build version and keeps five documented feature updates', () {
    final releases = recentReleases('0.51.0 (51)');
    expect(releases, hasLength(5));
    expect(releases.first.version, '0.51.0');
    expect(releases.map((r) => r.version).toSet(), hasLength(5));
    expect(releases.every((r) => r.changes.isNotEmpty), isTrue);
    expect(releases[1].version, '0.62.0');
    expect(releases.last.version, '0.49.0');
  });
}
