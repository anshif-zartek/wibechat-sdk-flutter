import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wibechat_example/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the connect screen', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const WibeChatExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('Flutter SDK example'), findsOneWidget);
    expect(find.text('Connect to a room'), findsOneWidget);
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Token'), findsOneWidget);
    expect(find.text('E2EE Key'), findsOneWidget);
    expect(find.text('CONNECT'), findsOneWidget);
  });
}
