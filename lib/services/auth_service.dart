// lib/services/auth_service.dart

import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

/// Classe d'aide pour ajouter des en-têtes authentifiés au client HTTP
class AuthenticatedClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client;

  AuthenticatedClient(this._headers, this._client);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
  }
}

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? _user;
  bool _rememberMe = false;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      gmail.GmailApi.gmailSendScope,
      'openid',
      'profile',
      'email',
    ],
  );

  gmail.GmailApi? _gmailApi;

  AuthService() {
    _auth.authStateChanges().listen((User? user) {
      _user = user;
      if (user == null) {
        _gmailApi = null;
      } else {
        initializeUser(user);
      }
      notifyListeners();
    });
    _loadRememberMePreference();
  }

  User? get currentUser => _user;
  bool get isAuthenticated => _user != null;
  bool get rememberMe => _rememberMe;

  Future<void> _loadRememberMePreference() async {
    final prefs = await SharedPreferences.getInstance();
    _rememberMe = prefs.getBool('remember_me') ?? false;
    notifyListeners();
  }

  Future<void> setRememberMe(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_me', value);
    _rememberMe = value;
    notifyListeners();
  }

  /// Initialiser le document utilisateur dans Firestore
  Future<void> initializeUser(User user) async {
    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await userRef.set({
        'email': user.email,
        'displayName': user.displayName,
        'photoURL': user.photoURL,
        'lastLogin': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      print('Document utilisateur initialisé pour ${user.uid}');
    } catch (e) {
      print('Erreur lors de l\'initialisation du document utilisateur: $e');
    }
  }

  Future<void> _initGmailApi() async {
    if (_gmailApi != null || _user == null) return;

    final googleSignInAccount = await _googleSignIn.signInSilently();
    if (googleSignInAccount == null) {
      print('Aucun compte Google trouvé pour l\'API Gmail.');
      return;
    }

    final authHeaders = await googleSignInAccount.authHeaders;
    final authenticatedClient = AuthenticatedClient(authHeaders, http.Client());
    _gmailApi = gmail.GmailApi(authenticatedClient);
  }

  /// Connexion avec Google
  Future<bool> signInWithGoogle() async {
    try {
      GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) return false;

      final auth = await account.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );

      await _auth.signInWithCredential(credential);

      await _initGmailApi();
      notifyListeners();
      await setRememberMe(true);
      print('Connexion avec Google réussie pour ${_auth.currentUser?.uid}');
      return true;
    } catch (e) {
      print('Erreur lors de la connexion avec Google: $e');
      return false;
    }
  }

  /// Connexion avec e-mail et mot de passe
  Future<UserCredential> signInWithEmailAndPassword(
    String email,
    String password, {
    bool rememberDevice = false,
  }) async {
    try {
      if (kIsWeb) {
        await _auth.setPersistence(
          rememberDevice ? Persistence.LOCAL : Persistence.SESSION,
        );
      } else {
        await _auth.setPersistence(
          rememberDevice ? Persistence.LOCAL : Persistence.NONE,
        );
      }

      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      await setRememberMe(rememberDevice);
      if (credential.user != null) {
        await initializeUser(credential.user!);
      }

      print('Connexion avec email réussie pour ${credential.user?.uid}');
      return credential;
    } catch (e) {
      print('Erreur lors de la connexion par email: $e');
      rethrow;
    }
  }

  /// Création d'un compte avec e-mail et mot de passe
  Future<UserCredential> createUserWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user != null) {
        await initializeUser(credential.user!);
      }

      print('Création de compte réussie pour ${credential.user?.uid}');
      return credential;
    } catch (e) {
      print('Erreur lors de la création du compte: $e');
      rethrow;
    }
  }

  /// Déconnexion
  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.disconnect();
    _gmailApi = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('remember_me');
    notifyListeners();
    print('Utilisateur déconnecté');
  }

  /// Envoi d'un e-mail via Gmail API
  Future<void> sendEmail({
    required String recipientEmail,
    required String subject,
    required String bodyText,
    String? bodyHtml,
  }) async {
    await _initGmailApi();
    if (_gmailApi == null) {
      throw Exception('L\'API Gmail n\'est pas initialisée.');
    }

    final emailContent = '''
From: ${_user!.email}
To: $recipientEmail
Subject: $subject
Content-Type: text/html; charset=UTF-8

${bodyHtml ?? bodyText}
''';

    final encodedEmail = base64Url.encode(utf8.encode(emailContent));
    final message = gmail.Message()..raw = encodedEmail;

    await _gmailApi!.users.messages.send(message, 'me');
    print('E-mail envoyé à $recipientEmail');
  }

  /// Méthode pour mettre à jour le nom affiché
  Future<void> updateDisplayName(String displayName) async {
    if (_auth.currentUser != null) {
      await _auth.currentUser!.updateDisplayName(displayName);
      await _auth.currentUser!.reload();
      _user = _auth.currentUser;
      notifyListeners();
    }
  }
}
