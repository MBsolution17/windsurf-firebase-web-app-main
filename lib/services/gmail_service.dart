// lib/services/gmail_service.dart
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'email_service.dart';

class GmailService implements EmailService {
  final http.Client _client;
  final String _username;

  GmailService(this._client, this._username);

  @override
  String get username => _username;

  @override
  Future<void> sendInvitationEmail({
    required String recipientEmail,
    required String senderName,
    required String subject,
    required String bodyText,
    String? bodyHtml,
  }) async {
    final gmailApi = gmail.GmailApi(_client);

    final message = gmail.Message()
      ..raw = _createRawMessage(recipientEmail, subject, bodyText, bodyHtml);

    await gmailApi.users.messages.send(message, 'me');
  }

  String _createRawMessage(
      String to, String subject, String bodyText, String? bodyHtml) {
    final message = StringBuffer();
    message.writeln('To: $to');
    message.writeln('Subject: $subject');
    message.writeln('Content-Type: text/html; charset="utf-8"');
    message.writeln();
    message.writeln(bodyHtml ?? bodyText);

    return base64Url.encode(utf8.encode(message.toString()));
  }
}
