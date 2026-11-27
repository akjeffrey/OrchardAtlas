import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/icon_importer.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/domain/map_icons.dart';
import 'package:orchard_atlas/ui/icon_image_search_dialog.dart';
import 'package:orchard_atlas/ui/icon_library_screen.dart';

class RecordingImageSearch implements IconImageSearch {
  final queries = <String>[];
  bool fail = false;
  @override
  Future<void> search(String query) async {
    if (fail) {
      throw PlatformException(code: 'browser_unavailable', message: 'Enable a web browser.');
    }
    queries.add(query);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Google Images URI encodes only the explicit query and validates its bounds', () {
    final uri = googleIconImageSearchUri('  pêche & pear + tree?  ');
    expect(uri.scheme, 'https');
    expect(uri.host, 'www.google.com');
    expect(uri.path, '/search');
    expect(uri.queryParameters, {'tbm':'isch','q':'pêche & pear + tree?'});
    expect(() => googleIconImageSearchUri('  '), throwsArgumentError);
    expect(() => googleIconImageSearchUri('x' * 201), throwsArgumentError);
  });
  test('device adapter sends a browser search URL without importing image data', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      DeviceIconImporter.channel,
      (call) async { calls.add(call); return null; },
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(DeviceIconImporter.channel,null));
    await DeviceIconImageSearch().search('pear tree');
    expect(calls, hasLength(1));
    expect(calls.single.method, 'searchIconImages');
    final uri = Uri.parse((calls.single.arguments as Map)['url'] as String);
    expect(uri.queryParameters['q'], 'pear tree');
    expect(uri.queryParameters['tbm'], 'isch');
  });
  Widget searchApp(RecordingImageSearch search) => ProviderScope(
    overrides: [iconImageSearchProvider.overrideWithValue(search)],
    child: MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () => showDialog<bool>(context:context,builder:(_)=>const IconImageSearchDialog()),
      child:const Text('Open search'),
    )))),
  );
  testWidgets('empty searches validate and cancellation never opens the browser', (tester) async {
    final search = RecordingImageSearch();
    await tester.pumpWidget(searchApp(search));
    await tester.tap(find.text('Open search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search images'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a search of 1–200 characters.'), findsOneWidget);
    expect(search.queries, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(IconImageSearchDialog), findsNothing);
    expect(search.queries, isEmpty);
  });
  testWidgets('failed browser launch retains the query and successful retry closes the dialog', (tester) async {
    final search = RecordingImageSearch()..fail = true;
    await tester.pumpWidget(searchApp(search));
    await tester.tap(find.text('Open search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'blueberry icon');
    await tester.tap(find.text('Search images'));
    await tester.pumpAndSettle();
    expect(find.text('Enable a web browser.'), findsOneWidget);
    expect(find.text('blueberry icon'), findsOneWidget);
    search.fail = false;
    await tester.tap(find.text('Search images'));
    await tester.pumpAndSettle();
    expect(search.queries, ['blueberry icon']);
    expect(find.byType(IconImageSearchDialog), findsNothing);
  });
  testWidgets('icon library offers Google search and preserves device import', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalTrialRepository.open(await SharedPreferences.getInstance());
    final search = RecordingImageSearch();
    await tester.pumpWidget(ProviderScope(overrides:[
      orchardRepositoryProvider.overrideWithValue(repo),
      authRepositoryProvider.overrideWithValue(TrialAuthRepository()),
      placeProvider.overrideWith((ref) async => repo.place),
      iconImageSearchProvider.overrideWithValue(search),
    ],child:const MaterialApp(home:IconLibraryScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Import image'), findsOneWidget);
    await tester.tap(find.text('Search Google Images'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'pear icon');
    await tester.tap(find.text('Search images'));
    await tester.pumpAndSettle();
    expect(search.queries, ['pear icon']);
    expect(find.text('Import image'), findsOneWidget);
    expect(find.text('No custom icons yet.'), findsOneWidget);
    expect((await tester.runAsync(() => repo.watchIcons(repo.place.id).first)),isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
