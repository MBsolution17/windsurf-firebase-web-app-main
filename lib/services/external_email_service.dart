// lib/services/external_email_service.dart

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'email_service.dart';

class ExternalEmailService implements EmailService {
  final String _email;
  final String _password;
  final String _smtpServer;
  final int _smtpPort;

  ExternalEmailService({
    required String email,
    required String password,
    required String smtpServer,
    required int smtpPort,
  })  : _email = email,
        _password = password,
        _smtpServer = smtpServer,
        _smtpPort = smtpPort;

  @override
  String get username => _email;

  @override
  Future<void> sendInvitationEmail({
    required String recipientEmail,
    required String senderName,
    required String subject,
    required String bodyText,
    String? bodyHtml,
  }) async {
    final smtp = SmtpServer(
      _smtpServer,
      port: _smtpPort,
      username: _email,
      password: _password,
      ignoreBadCertificate: false,
    );

    final message = Message()
      ..from = Address(_email, senderName)
      ..recipients.add(recipientEmail)
      ..subject = subject
      ..text = bodyText
      ..html = bodyHtml ?? bodyText;

    try {
      final sendReport = await send(message, smtp);
      print('Message envoyé: $sendReport');
    } on MailerException catch (e) {
      print('Erreur lors de l\'envoi du message: $e');
      for (var p in e.problems) {
        print('Problème: ${p.code}: ${p.msg}');
      }
      rethrow;
    }
  }
}
