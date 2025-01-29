// lib/widgets/profile_avatar.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class ProfileAvatar extends StatefulWidget {
  final double radius;

  const ProfileAvatar({Key? key, this.radius = 50}) : super(key: key);

  @override
  _ProfileAvatarState createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  bool _isUpdating = false;
  Uint8List? _selectedImageBytes;
  String? _photoURL;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  /// Charge les informations actuelles de l'utilisateur
  void _loadUserProfile() async {
    User? user = _auth.currentUser;
    if (user != null) {
      try {
        DocumentSnapshot userDoc = await _firestore.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          setState(() {
            _photoURL = userDoc['photoURL'] ?? user.photoURL;
          });
        } else {
          setState(() {
            _photoURL = user.photoURL;
          });
        }
      } catch (e) {
        debugPrint('Erreur lors du chargement du profil : $e');
      }
    }
  }

  /// Sélectionne une image à partir de la galerie ou de la caméra
  Future<void> _selectImage() async {
    final ImagePicker _picker = ImagePicker();
    // Demander à l'utilisateur de choisir la source de l'image
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galerie'),
              onTap: () async {
                Navigator.of(context).pop();
                final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
                if (pickedFile != null) {
                  Uint8List imageBytes = await pickedFile.readAsBytes();
                  setState(() {
                    _selectedImageBytes = imageBytes;
                  });
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Caméra'),
              onTap: () async {
                Navigator.of(context).pop();
                final XFile? pickedFile = await _picker.pickImage(source: ImageSource.camera);
                if (pickedFile != null) {
                  Uint8List imageBytes = await pickedFile.readAsBytes();
                  setState(() {
                    _selectedImageBytes = imageBytes;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Télécharge l'image sélectionnée vers Firebase Storage et retourne l'URL
  Future<String?> _uploadProfilePicture(Uint8List imageBytes, String uid) async {
    try {
      String filePath = 'profile_pictures/$uid.jpg';
      Reference ref = _storage.ref().child(filePath);
      UploadTask uploadTask = ref.putData(imageBytes, SettableMetadata(contentType: 'image/jpeg'));

      TaskSnapshot snapshot = await uploadTask;
      String downloadURL = await snapshot.ref.getDownloadURL();
      return downloadURL;
    } catch (e) {
      debugPrint('Erreur lors du téléchargement de la photo de profil : $e');
      return null;
    }
  }

  /// Met à jour la photo de profil de l'utilisateur
  Future<void> _updateProfilePicture() async {
    setState(() {
      _isUpdating = true;
    });

    User? user = _auth.currentUser;
    if (user != null && _selectedImageBytes != null) {
      try {
        String? uploadedURL = await _uploadProfilePicture(_selectedImageBytes!, user.uid);
        if (uploadedURL != null) {
          await user.updatePhotoURL(uploadedURL);
          await _firestore.collection('users').doc(user.uid).set({
            'photoURL': uploadedURL,
          }, SetOptions(merge: true));

          // Rafraîchir les données locales
          await user.reload();
          User? updatedUser = _auth.currentUser;
          setState(() {
            _photoURL = updatedUser?.photoURL;
            _selectedImageBytes = null;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Photo de profil mise à jour avec succès')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la mise à jour : $e')),
        );
        debugPrint('Erreur lors de la mise à jour de la photo de profil : $e');
      } finally {
        setState(() {
          _isUpdating = false;
        });
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune image sélectionnée')),
      );
      setState(() {
        _isUpdating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CircleAvatar(
          radius: widget.radius,
          backgroundColor: Colors.indigo[800],
          backgroundImage: _selectedImageBytes != null
              ? MemoryImage(_selectedImageBytes!)
              : (_photoURL != null
                  ? NetworkImage(_photoURL!)
                  : null) as ImageProvider<Object>?,
          child: _selectedImageBytes == null && _photoURL == null
              ? Text(
                  _auth.currentUser?.displayName != null &&
                          _auth.currentUser!.displayName!.isNotEmpty
                      ? _auth.currentUser!.displayName![0].toUpperCase()
                      : '?',
                  style: const TextStyle(color: Colors.white, fontSize: 40),
                )
              : null,
        ),
        if (_selectedImageBytes != null)
          Positioned(
            bottom: -10,
            right: -10,
            child: GestureDetector(
              onTap: _updateProfilePicture,
              child: CircleAvatar(
                backgroundColor: Colors.green,
                radius: 16,
                child: _isUpdating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 18,
                      ),
              ),
            ),
          ),
      ],
    );
  }
}
