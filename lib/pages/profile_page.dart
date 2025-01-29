// lib/pages/profile_page.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

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
            _displayNameController.text = userDoc['displayName'] ?? user.displayName ?? '';
            _photoURL = userDoc['photoURL'] ?? user.photoURL;
          });
        } else {
          setState(() {
            _displayNameController.text = user.displayName ?? '';
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
  
  /// Met à jour le profil de l'utilisateur
  Future<void> _updateProfile() async {
    setState(() {
      _isUpdating = true;
    });
  
    User? user = _auth.currentUser;
    if (user != null) {
      String newDisplayName = _displayNameController.text.trim();
  
      try {
        // Mettre à jour le nom dans Firebase Auth
        await user.updateDisplayName(newDisplayName);
  
        String? photoURL = _photoURL;
  
        // Téléchargez une nouvelle photo si une image est sélectionnée
        if (_selectedImageBytes != null) {
          String? uploadedURL = await _uploadProfilePicture(_selectedImageBytes!, user.uid);
          if (uploadedURL != null) {
            photoURL = uploadedURL;
            await user.updatePhotoURL(photoURL);
          }
        }
  
        await user.reload();
        User? updatedUser = _auth.currentUser;
  
        if (updatedUser != null) {
          // Mettre à jour Firestore
          await _firestore.collection('users').doc(updatedUser.uid).set({
            'displayName': newDisplayName,
            'photoURL': photoURL,
          }, SetOptions(merge: true));
  
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profil mis à jour avec succès')),
          );
  
          // Rafraîchir l'état local
          setState(() {
            _photoURL = photoURL;
            _selectedImageBytes = null;
          });
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la mise à jour : $e')),
        );
        debugPrint('Erreur lors de la mise à jour du profil : $e');
      } finally {
        setState(() {
          _isUpdating = false;
        });
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Utilisateur non authentifié')),
      );
      setState(() {
        _isUpdating = false;
      });
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
              content: SingleChildScrollView(
                child: Column(
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
              ),
              actions: [
                TextButton(
                  child: const Text('Annuler'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  child: _isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Enregistrer'),
                  onPressed: _isProcessing
                      ? null
                      : () async {
                          String newPassword = _newPasswordController.text.trim();
                          String confirmPassword = _confirmPasswordController.text.trim();
                          
                          if (newPassword.isEmpty || confirmPassword.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Tous les champs sont requis')),
                            );
                            return;
                          }
                          
                          if (newPassword != confirmPassword) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Les mots de passe ne correspondent pas')),
                            );
                            return;
                          }
                          
                          if (newPassword.length < 6) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Le mot de passe doit contenir au moins 6 caractères')),
                            );
                            return;
                          }
                          
                          setStateDialog(() {
                            _isProcessing = true;
                          });
                          
                          User? user = _auth.currentUser;
                          if (user != null) {
                            try {
                              await user.updatePassword(newPassword);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Mot de passe mis à jour avec succès')),
                              );
                              Navigator.of(context).pop();
                            } on FirebaseAuthException catch (e) {
                              if (e.code == 'requires-recent-login') {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Veuillez vous reconnecter pour changer le mot de passe')),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Erreur: ${e.message}')),
                                );
                              }
                              debugPrint('Erreur lors de la mise à jour du mot de passe: $e');
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Erreur: $e')),
                              );
                              debugPrint('Erreur lors de la mise à jour du mot de passe: $e');
                            } finally {
                              setStateDialog(() {
                                _isProcessing = false;
                              });
                            }
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Utilisateur non authentifié')),
                            );
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
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    User? user = _auth.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon Profil'),
        backgroundColor: Colors.grey[800],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Avatar avec bouton d'édition
              Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.indigo[800],
                    backgroundImage: _selectedImageBytes != null
                        ? MemoryImage(_selectedImageBytes!)
                        : (_photoURL != null
                            ? NetworkImage(_photoURL!)
                            : null) as ImageProvider<Object>?,
                    child: _selectedImageBytes == null && _photoURL == null
                        ? Text(
                            user?.displayName != null && user!.displayName!.isNotEmpty
                                ? user.displayName![0].toUpperCase()
                                : '?',
                            style: const TextStyle(color: Colors.white, fontSize: 40),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _selectImage,
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
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Champ pour le nom affiché
              TextField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'Nom Affiché',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              // Email (non éditable)
              TextField(
                controller: TextEditingController(text: user?.email ?? ''),
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                readOnly: true,
              ),
              const SizedBox(height: 20),
              // Bouton pour changer le mot de passe
              ElevatedButton.icon(
                onPressed: _showChangePasswordDialog,
                icon: const Icon(Icons.lock),
                label: const Text('Changer le Mot de Passe'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  textStyle: GoogleFonts.roboto(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Bouton de mise à jour
              ElevatedButton(
                onPressed: _isUpdating ? null : _updateProfile,
                child: _isUpdating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Mettre à Jour'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  textStyle: GoogleFonts.roboto(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
