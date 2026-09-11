import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/servers/server_models.dart';

void main() {
  group('detectedAuthAnswers', () {
    test('answers a password prompt from the saved credential', () {
      expect(detectedAuthAnswers(const ['Password: '], 'hunter2'), ['hunter2']);
    });

    test('defers a verification-code prompt to the user', () {
      // Regression for bastions that ask for the password and then a second
      // factor: answering the code prompt with the password made the login
      // fail with only "keyboard-interactive" advertised.
      expect(
        detectedAuthAnswers(const [
          'Password: ',
          'Verification code: ',
        ], 'hunter2'),
        ['hunter2', null],
      );
    });

    test('defers code and menu prompts to the user', () {
      expect(
        detectedAuthAnswers(const [
          'One-time password: ',
          'Select an asset: ',
        ], 'hunter2'),
        [null, null],
      );
    });

    test('answers localized password prompts', () {
      expect(detectedAuthAnswers(const ['密码：'], 'hunter2'), ['hunter2']);
      expect(detectedAuthAnswers(const ['密碼：'], 'hunter2'), ['hunter2']);
    });

    test('offers nothing without a stored password', () {
      expect(detectedAuthAnswers(const ['Password: '], null), [null]);
      expect(detectedAuthAnswers(const ['Password: '], ''), [null]);
    });

    test('keeps one answer per prompt for an empty challenge', () {
      expect(detectedAuthAnswers(const [], 'hunter2'), isEmpty);
    });
  });
}
