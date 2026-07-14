import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

Widget _host(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets('has one box per digit', (tester) async {
    await tester.pumpWidget(_host(
      OtpInput(length: 6, autofocus: false, onChanged: (_) {}),
    ));
    expect(find.byType(TextField), findsNWidgets(6));
  });

  testWidgets('collects digits across boxes and reports completion',
      (tester) async {
    String latest = '';
    String? completed;

    await tester.pumpWidget(_host(OtpInput(
      autofocus: false,
      onChanged: (code) => latest = code,
      onCompleted: (code) => completed = code,
    )));

    const code = '123456';
    final boxes = find.byType(TextField);
    for (var i = 0; i < 6; i++) {
      await tester.enterText(boxes.at(i), code[i]);
      await tester.pump();
    }

    expect(latest, code);
    expect(completed, code);
  });
}
