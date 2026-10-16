import 'package:flutter/material.dart';
import 'package:wibechat_client/wibechat_client.dart';
import 'package:wibechat_example/theme.dart';
import 'package:logging/logging.dart';
import 'package:intl/intl.dart';
import 'pages/connect.dart';

void main() async {
  final format = DateFormat('HH:mm:ss');
  // configure logs for debugging
  Logger.root.level = Level.FINEST;
  Logger.root.onRecord.listen((record) {
    print('${format.format(record.time)} [${record.level.name}]: ${record.message}');
  });

  WidgetsFlutterBinding.ensureInitialized();
  /*if (lkPlatformIsDesktop()) {
    await FlutterWindowClose.setWindowShouldCloseHandler(() async {
      await onWindowShouldClose?.call();
      return true;
    });
  }*/

  /// for livestreaming app, you can initialize the bypassVoiceProcessing = true
  /// here to get better audio quality
  ///
  /// await WibeChatClient.initialize(
  ///  bypassVoiceProcessing: lkPlatformIsMobile(),
  /// );
  await WibeChatClient.initialize(
    zeroPlayoutDelay: true,
    enableWARP: true,
  );
  runApp(const WibeChatExampleApp());
}

class WibeChatExampleApp extends StatelessWidget {
  //
  const WibeChatExampleApp({
    super.key,
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'WibeChat Flutter Example',
        theme: WibeChatTheme().buildThemeData(context),
        home: const ConnectPage(),
      );
}
