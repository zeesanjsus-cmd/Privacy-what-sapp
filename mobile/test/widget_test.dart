import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_whatsapp/main.dart';

void main() {
  testWidgets('Privacy WhatsApp login screen renders', (tester) async {
    await tester.pumpWidget(const App());
    expect(find.text('Privacy WhatsApp'), findsOneWidget);
    expect(find.text('Send OTP'), findsOneWidget);
  });
}
