import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ProfileAvatar extends StatelessWidget {
  final double radius;
  final Uint8List? displayImageBytes; // Pour Flutter Web
  final String? photoURL; // URL de la photo stockée

  const ProfileAvatar({
    Key? key,
    this.radius = 50,
    this.displayImageBytes,
    this.photoURL,
  }) : super(key: key);

  // URL de la fonction Firebase déployée (optionnel si tu passes displayImageBytes)
  static const String _firebaseFunctionUrl = 'https://getprofileimage-iu4ydislpq-uc.a.run.app';

  /// Détermine l'ImageProvider à utiliser pour CircleAvatar
  ImageProvider<Object>? _getImageProvider(User? user) {
    if (displayImageBytes != null) {
      return MemoryImage(displayImageBytes!);
    }
    if (photoURL != null) {
      if (kIsWeb) {
        // Sur Web, on s'appuie sur displayImageBytes fourni par le parent
        return null; // Pas de NetworkImage direct à cause de CORS
      } else {
        return NetworkImage(photoURL!);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    ImageProvider<Object>? imageProvider = _getImageProvider(user);

    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.indigo[800],
      backgroundImage: imageProvider,
      child: imageProvider == null
          ? Text(
              user?.displayName != null && user!.displayName!.isNotEmpty
                  ? user.displayName![0].toUpperCase()
                  : '?',
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * 0.8,
              ),
            )
          : null,
    );
  }
}