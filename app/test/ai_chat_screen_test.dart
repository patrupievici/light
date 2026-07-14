import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/screens/ai/ai_chat_screen.dart';
import 'package:zvelt_app/services/ai_chat_service.dart';

class _FakeAiChatService extends AiChatService {
  String? receivedQuestion;
  bool? receivedCreateWorkout;

  @override
  Future<Map<String, dynamic>> askTrainer(
    String question, {
    bool createWorkout = false,
  }) async {
    receivedQuestion = question;
    receivedCreateWorkout = createWorkout;
    return {
      'trainer': {'answer': 'Try a balanced lunch.'},
    };
  }
}

void main() {
  testWidgets('coach chat never creates a workout as a message side effect',
      (tester) async {
    final service = _FakeAiChatService();

    await tester.pumpWidget(
      MaterialApp(
        home: AiChatScreen(
          aiService: service,
          profileLoader: () async => null,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Suggest a lunch'));
    await tester.pumpAndSettle();

    expect(service.receivedQuestion, 'Suggest a lunch');
    expect(service.receivedCreateWorkout, isFalse);
    expect(find.text('Try a balanced lunch.'), findsOneWidget);
    expect(find.text('Complete workout'), findsNothing);
  });
}
