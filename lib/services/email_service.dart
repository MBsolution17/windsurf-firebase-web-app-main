// lib/services/email_service.dart

abstract class EmailService {
  String get username;

  Future<void> sendInvitationEmail({
    required String recipientEmail,
    required String senderName,
    required String subject,
    required String bodyText,
    String? bodyHtml,
  });
}
