import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../widgets/profile_avatar.dart'; // Assurez-vous d'importer votre widget ProfileAvatar

class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  final TextEditingController _displayNameController = TextEditingController();
  Uint8List? _selectedImageBytes; // Image sélectionnée localement
  bool _isUpdating = false;
  String? _errorMessage;

  // URL de la fonction Firebase déployée
  final String _firebaseFunctionUrl = 'https://getprofileimage-iu4ydislpq-uc.a.run.app';

  @override
  void initState() {
    super.initState();
    _loadInitialProfile();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  /// Charge les données initiales du profil
  Future<void> _loadInitialProfile() async {
    User? user = _auth.currentUser;
    if (user != null) {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        _displayNameController.text = userDoc['displayName'] ?? user.displayName ?? '';
      } else {
        _displayNameController.text = user.displayName ?? '';
      }
    }
  }

  /// Charge l'image pour Flutter Web via Firebase Function
  Future<Uint8List?> _loadProfileImage(String? photoURL) async {
    if (photoURL == null || !kIsWeb) return null;
    try {
      final response = await http.get(
        Uri.parse('$_firebaseFunctionUrl?url=${Uri.encodeComponent(photoURL)}'),
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['imageBase64'] != null) {
          return base64Decode(json['imageBase64']);
        }
      }
    } catch (e) {
      debugPrint('Erreur lors du chargement de l’image via Firebase Function : $e');
    }
    return null;
  }

  /// Sélectionne une image à partir de la galerie ou de la caméra
  Future<void> _selectImage() async {
    final ImagePicker picker = ImagePicker();
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
                final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);
                if (pickedFile != null && mounted) {
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
                final XFile? pickedFile = await picker.pickImage(source: ImageSource.camera);
                if (pickedFile != null && mounted) {
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

  /// Télécharge l'image sélectionnée vers Firebase Storage
  Future<String?> _uploadProfilePicture(Uint8List imageBytes, String uid) async {
    try {
      String filePath = 'profile_pictures/$uid.jpg';
      Reference ref = _storage.ref().child(filePath);
      await ref.putData(imageBytes, SettableMetadata(contentType: 'image/jpeg'));
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Erreur lors du téléversement de la photo de profil : $e');
      setState(() {
        _errorMessage = 'Erreur lors du téléversement : $e';
      });
      return null;
    }
  }

  /// Met à jour le profil de l'utilisateur
  Future<void> _updateProfile() async {
    setState(() {
      _isUpdating = true;
      _errorMessage = null;
    });

    User? user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _isUpdating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Utilisateur non authentifié')),
      );
      return;
    }

    String newDisplayName = _displayNameController.text.trim();

    try {
      String? photoURL = user.photoURL;

      if (_selectedImageBytes != null) {
        photoURL = await _uploadProfilePicture(_selectedImageBytes!, user.uid);
        if (photoURL != null) {
          await user.updatePhotoURL(photoURL);
        }
      }

      await user.updateDisplayName(newDisplayName);
      await user.reload();
      User? updatedUser = _auth.currentUser;

      if (updatedUser != null && mounted) {
        await _firestore.collection('users').doc(updatedUser.uid).set({
          'displayName': newDisplayName,
          'photoURL': photoURL,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        setState(() {
          _isUpdating = false;
          _selectedImageBytes = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil mis à jour avec succès')),
        );
      }
    } catch (e) {
      debugPrint('Erreur lors de la mise à jour du profil : $e');
      setState(() {
        _isUpdating = false;
        _errorMessage = 'Erreur lors de la mise à jour : $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage ?? 'Erreur inconnue')),
      );
    }
  }

  /// Ouvre une boîte de dialogue pour changer le mot de passe
  void _showChangePasswordDialog() {
    final TextEditingController _newPasswordController = TextEditingController();
    final TextEditingController _confirmPasswordController = TextEditingController();
    bool _isProcessing = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Changer le Mot de Passe'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _newPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Nouveau Mot de Passe',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirmer le Mot de Passe',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  child: const Text('Annuler'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  child: _isProcessing
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Enregistrer'),
                  onPressed: _isProcessing
                      ? null
                      : () async {
                          String newPassword = _newPasswordController.text.trim();
                          String confirmPassword = _confirmPasswordController.text.trim();

                          if (newPassword != confirmPassword) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Les mots de passe ne correspondent pas')),
                            );
                            return;
                          }

                          setStateDialog(() {
                            _isProcessing = true;
                          });

                          try {
                            await _auth.currentUser!.updatePassword(newPassword);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Mot de passe mis à jour')),
                            );
                            Navigator.of(context).pop();
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Erreur : $e')),
                            );
                          } finally {
                            setStateDialog(() {
                              _isProcessing = false;
                            });
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon Profil'),
        backgroundColor: Colors.grey[800],
      ),
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.userChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          User? user = snapshot.data;
          if (user == null) {
            return const Center(child: Text('Utilisateur non authentifié'));
          }

          _displayNameController.text = user.displayName ?? _displayNameController.text;

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      kIsWeb
                          ? FutureBuilder<Uint8List?>(
                              future: _loadProfileImage(user.photoURL),
                              builder: (context, imageSnapshot) {
                                return GestureDetector(
                                  onTap: _selectImage,
                                  child: ProfileAvatar(
                                    radius: 50,
                                    photoURL: user.photoURL,
                                    displayImageBytes: _selectedImageBytes ?? imageSnapshot.data,
                                  ),
                                );
                              },
                            )
                          : GestureDetector(
                              onTap: _selectImage,
                              child: ProfileAvatar(
                                radius: 50,
                                photoURL: user.photoURL,
                                displayImageBytes: _selectedImageBytes,
                              ),
                            ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          radius: 16,
                          child: const Icon(
                            Icons.edit,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                      if (_selectedImageBytes != null)
                        Positioned(
                          bottom: -10,
                          right: -10,
                          child: GestureDetector(
                            onTap: _updateProfile,
                            child: CircleAvatar(
                              backgroundColor: Colors.green,
                              radius: 16,
                              child: _isUpdating
                                  ? const CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
                  ),
                  const SizedBox(height: 20),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  TextField(
                    controller: _displayNameController,
                    decoration: const InputDecoration(
                      labelText: 'Nom Affiché',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: TextEditingController(text: user.email ?? ''),
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    readOnly: true,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _showChangePasswordDialog,
                    icon: const Icon(Icons.lock),
                    label: const Text('Changer le Mot de Passe'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isUpdating ? null : _updateProfile,
                    child: _isUpdating
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Mettre à Jour'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}