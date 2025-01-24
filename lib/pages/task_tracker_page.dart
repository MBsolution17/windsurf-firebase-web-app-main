import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:firebase_web_app/models/task.dart'; // Import du modèle Task avec TaskStatus, TaskPriority
import 'package:firebase_web_app/pages/calendar_page.dart'; 
import 'package:firebase_auth/firebase_auth.dart'; 

/// Modèle de Données pour un Utilisateur
class UserModel {
  final String uid;
  final String displayName;
  final String email;

  UserModel({
    required this.uid,
    required this.displayName,
    required this.email,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: data['uid'] ?? '',
      displayName: data['displayName'] ?? '',
      email: data['email'] ?? '',
    );
  }
}

/// Page de Gestion des Tâches
class TaskTrackerPage extends StatefulWidget {
  const TaskTrackerPage({super.key});

  @override
  _TaskTrackerPageState createState() => _TaskTrackerPageState();
}

class _TaskTrackerPageState extends State<TaskTrackerPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = Uuid();

  // Filtres
  TaskStatus? _filterStatus;
  TaskPriority? _filterPriority;

  // Barre de recherche
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Liste des utilisateurs (utilisateur actuel + amis filtrés)
  List<UserModel> _users = [];

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Méthode pour récupérer la liste des utilisateurs et amis depuis Firestore
  Future<void> _fetchUsers() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) return;

      // Récupérer les informations de l'utilisateur actuel
      final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      if (!userDoc.exists) {
        // Si l'utilisateur n'est pas trouvé
        setState(() {
          _users = [];
        });
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final currentUserModel = UserModel(
        uid: currentUser.uid,
        displayName: userData['displayName'] ?? 'Moi',
        email: userData['email'] ?? 'Inconnu',
      );

      // Récupérer les amis depuis la sous-collection 'friends'
      QuerySnapshot friendsSnapshot = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('friends')
          .orderBy('timestamp', descending: true)
          .get();

      List<UserModel> friends = friendsSnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return UserModel(
          uid: data['uid'] ?? '',
          displayName: data['displayName'] ?? 'Inconnu',
          email: data['email'] ?? 'Inconnu',
        );
      }).toList();

      // On ne garde que les amis dont l'uid n'est pas vide
      friends = friends.where((friend) => friend.uid.isNotEmpty).toList();

      setState(() {
        _users = [currentUserModel, ...friends];
      });
    } catch (e) {
      debugPrint('Erreur lors de la récupération des utilisateurs: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la récupération des utilisateurs: $e')),
      );
    }
  }

  /// Méthode pour ajouter une tâche
  Future<void> _addTask(
    GlobalKey<FormState> formKey,
    String title,
    String description,
    DateTime dueDate,
    String assignee,
    TaskStatus status,
    TaskPriority priority,
  ) async {
    if (formKey.currentState!.validate()) {
      formKey.currentState!.save();

      final assignedTo = assignee.isNotEmpty ? assignee : '';
      final assigneeName = _users.firstWhere(
        (user) => user.uid == assignedTo,
        orElse: () => UserModel(uid: '', displayName: 'Non assigné', email: ''),
      ).displayName;

      final newTask = Task(
        id: _uuid.v4(),
        title: title,
        description: description,
        dueDate: dueDate,
        assignee: assignedTo,
        assigneeName: assigneeName,
        status: status,
        priority: priority,
      );

      try {
        await _firestore.collection('tasks').doc(newTask.id).set(newTask.toMap());
        debugPrint('Tâche ajoutée avec succès.');
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tâche ajoutée avec succès.')),
        );
      } catch (e) {
        debugPrint('Erreur lors de l\'ajout de la tâche: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'ajout de la tâche: $e')),
        );
      }
    } else {
      debugPrint('Formulaire d\'ajout de tâche invalide.');
    }
  }

  /// Méthode pour mettre à jour une tâche
  Future<void> _updateTask(
    GlobalKey<FormState> formKey,
    Task task,
    String title,
    String description,
    DateTime dueDate,
    String assignee,
    TaskStatus status,
    TaskPriority priority,
  ) async {
    if (formKey.currentState!.validate()) {
      formKey.currentState!.save();

      final assignedTo = assignee.isNotEmpty ? assignee : '';
      final assigneeName = _users.firstWhere(
        (user) => user.uid == assignedTo,
        orElse: () => UserModel(uid: '', displayName: 'Non assigné', email: ''),
      ).displayName;

      final updatedTask = Task(
        id: task.id,
        title: title,
        description: description,
        dueDate: dueDate,
        assignee: assignedTo,
        assigneeName: assigneeName,
        status: status,
        priority: priority,
      );

      try {
        await _firestore.collection('tasks').doc(updatedTask.id).update(updatedTask.toMap());
        debugPrint('Tâche mise à jour avec succès.');
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tâche mise à jour avec succès.')),
        );
      } catch (e) {
        debugPrint('Erreur lors de la mise à jour de la tâche: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la mise à jour de la tâche: $e')),
        );
      }
    } else {
      debugPrint('Formulaire de mise à jour de tâche invalide.');
    }
  }

  /// Méthode pour supprimer une tâche
  Future<void> _deleteTask(String id) async {
    try {
      await _firestore.collection('tasks').doc(id).delete();
      debugPrint('Tâche supprimée avec succès.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tâche supprimée avec succès.')),
      );
    } catch (e) {
      debugPrint('Erreur lors de la suppression de la tâche: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la suppression de la tâche: $e')),
      );
    }
  }

  /// Fonction pour obtenir la couleur du statut
  Color _getStatusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.ToDo:
        return Colors.blue;
      case TaskStatus.InProgress:
        return Colors.orange;
      case TaskStatus.Done:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  /// Widget pour afficher chaque tâche dans la liste
  Widget _buildTaskCard(Task task) {
    Color priorityColor;
    switch (task.priority) {
      case TaskPriority.Low:
        priorityColor = Colors.green;
        break;
      case TaskPriority.Medium:
        priorityColor = Colors.orange;
        break;
      case TaskPriority.High:
        priorityColor = Colors.red;
        break;
      default:
        priorityColor = Colors.grey;
    }

    // Trouver le nom de l'assignee
    String assigneeName = 'Non assigné';
    if (task.assignee.isNotEmpty) {
      UserModel user = _users.firstWhere(
        (user) => user.uid == task.assignee,
        orElse: () => UserModel(uid: task.assignee, displayName: 'Inconnu', email: ''),
      );
      assigneeName = user.displayName.isNotEmpty ? user.displayName : 'Inconnu';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Slidable(
        key: ValueKey(task.id),
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          extentRatio: 0.4,
          children: [
            SlidableAction(
              onPressed: (context) => _showEditTaskDialog(task),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              icon: Icons.edit,
              label: 'Modifier',
            ),
            SlidableAction(
              onPressed: (context) => _deleteTask(task.id),
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              icon: Icons.delete,
              label: 'Supprimer',
            ),
          ],
        ),
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Titre + priorité
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        task.title,
                        style: GoogleFonts.lato(
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Chip(
                      label: Text(
                        task.priority.toString().split('.').last,
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: priorityColor,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Description
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    task.description,
                    style: GoogleFonts.lato(
                      textStyle: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 12),
                // Échéance + Assigné
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 16, color: Colors.blueGrey),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('dd/MM/yyyy').format(task.dueDate),
                          style: GoogleFonts.lato(
                            textStyle: const TextStyle(
                                fontSize: 12, color: Colors.blueGrey),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.person,
                            size: 16, color: Colors.blueGrey),
                        const SizedBox(width: 4),
                        Text(
                          assigneeName,
                          style: GoogleFonts.lato(
                            textStyle: const TextStyle(
                                fontSize: 12, color: Colors.blueGrey),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Statut
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    label: Text(
                      task.status.toString().split('.').last,
                      style: const TextStyle(color: Colors.white),
                    ),
                    backgroundColor: _getStatusColor(task.status),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Méthode pour construire les filtres
  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Wrap(
        spacing: 12.0,
        runSpacing: 12.0,
        children: [
          // Filtrer par Statut
          DropdownButton<TaskStatus>(
            hint: const Text('Filtrer par Statut'),
            value: _filterStatus,
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Tous les Statuts'),
              ),
              ...TaskStatus.values.map((status) {
                return DropdownMenuItem(
                  value: status,
                  child: Text(status.toString().split('.').last),
                );
              }),
            ],
            onChanged: (TaskStatus? newValue) {
              setState(() {
                _filterStatus = newValue;
              });
            },
          ),
          // Filtrer par Priorité
          DropdownButton<TaskPriority>(
            hint: const Text('Filtrer par Priorité'),
            value: _filterPriority,
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Toutes les Priorités'),
              ),
              ...TaskPriority.values.map((priority) {
                return DropdownMenuItem(
                  value: priority,
                  child: Text(priority.toString().split('.').last),
                );
              }),
            ],
            onChanged: (TaskPriority? newValue) {
              setState(() {
                _filterPriority = newValue;
              });
            },
          ),
          // Bouton Réinitialiser les filtres
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _filterStatus = null;
                _filterPriority = null;
                _searchQuery = '';
                _searchController.clear();
              });
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Réinitialiser'),
          ),
        ],
      ),
    );
  }

  /// Méthode pour construire le corps de la page
  Widget _buildBody() {
    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Center(child: Text('Utilisateur non connecté.'));
    }

    Query taskQuery = _firestore.collection('tasks');

    // Appliquer les filtres de statut et priorité
    if (_filterStatus != null) {
      taskQuery = taskQuery.where(
          'status', isEqualTo: _filterStatus.toString().split('.').last);
    }

    if (_filterPriority != null) {
      taskQuery = taskQuery.where(
          'priority', isEqualTo: _filterPriority.toString().split('.').last);
    }

    taskQuery = taskQuery.orderBy('dueDate');

    return Column(
      children: [
        // Barre de recherche
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Rechercher',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value.toLowerCase();
              });
            },
          ),
        ),
        // Filtres
        _buildFilters(),
        const SizedBox(height: 8),
        // Liste des tâches
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: taskQuery.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                debugPrint('Erreur dans StreamBuilder: ${snapshot.error}');
                return Center(child: Text('Erreur: ${snapshot.error}'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              List<Task> tasks = snapshot.data!.docs
                  .map((doc) => Task.fromFirestore(doc))
                  .toList();

              // Appliquer la recherche
              if (_searchQuery.isNotEmpty) {
                tasks = tasks.where((task) {
                  return task.title.toLowerCase().contains(_searchQuery) ||
                      task.description.toLowerCase().contains(_searchQuery);
                }).toList();
              }

              if (tasks.isEmpty) {
                return const Center(child: Text('Aucune tâche disponible.'));
              }

              return RefreshIndicator(
                onRefresh: () async {
                  await _fetchUsers();
                },
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 80.0),
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return _buildTaskCard(task);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Méthode pour afficher le formulaire d'ajout de tâche
  void _showAddTaskDialog() {
    String title = '';
    String description = '';
    DateTime dueDate = DateTime.now();
    String assignee = ''; // Par défaut 'Non Assigné'
    TaskStatus status = TaskStatus.ToDo;
    TaskPriority priority = TaskPriority.Low;

    final GlobalKey<FormState> addFormKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      Text(
                        'Ajouter une Tâche',
                        style: GoogleFonts.lato(
                          textStyle: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Form(
                        key: addFormKey,
                        child: Column(
                          children: [
                            TextFormField(
                              decoration: const InputDecoration(
                                labelText: 'Titre',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Veuillez entrer un titre';
                                }
                                return null;
                              },
                              onSaved: (value) => title = value!,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              decoration: const InputDecoration(
                                labelText: 'Description',
                                border: OutlineInputBorder(),
                              ),
                              maxLines: 3,
                              onSaved: (value) => description = value ?? '',
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.calendar_today,
                                    color: Colors.blue),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat('dd/MM/yyyy').format(dueDate),
                                  style: GoogleFonts.lato(fontSize: 16),
                                ),
                                const Spacer(),
                                ElevatedButton(
                                  onPressed: () async {
                                    DateTime? picked = await showDatePicker(
                                      context: context,
                                      initialDate: dueDate,
                                      firstDate: DateTime.now(),
                                      lastDate: DateTime(2100),
                                    );
                                    if (picked != null) {
                                      setState(() {
                                        dueDate = picked;
                                      });
                                    }
                                  },
                                  child: const Text('Changer'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Dropdown Assigné à
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Assigné à',
                                border: OutlineInputBorder(),
                              ),
                              // Si assignee n'est pas dans _users, on force à ''
                              value: _users.any((user) => user.uid == assignee) ? assignee : '',
                              items: [
                                const DropdownMenuItem<String>(
                                  value: '',
                                  child: Text('Non Assigné'),
                                ),
                                ..._users.map((UserModel user) => DropdownMenuItem<String>(
                                      value: user.uid,
                                      child: Text(user.displayName),
                                    )),
                              ],
                              onChanged: (newValue) {
                                setState(() {
                                  assignee = newValue ?? '';
                                });
                              },
                              onSaved: (value) => assignee = value ?? '',
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<TaskStatus>(
                              decoration: const InputDecoration(
                                labelText: 'Statut',
                                border: OutlineInputBorder(),
                              ),
                              value: status,
                              items: TaskStatus.values.map((TaskStatus status) {
                                return DropdownMenuItem<TaskStatus>(
                                  value: status,
                                  child:
                                      Text(status.toString().split('.').last),
                                );
                              }).toList(),
                              onChanged: (newValue) {
                                setState(() {
                                  status = newValue!;
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<TaskPriority>(
                              decoration: const InputDecoration(
                                labelText: 'Priorité',
                                border: OutlineInputBorder(),
                              ),
                              value: priority,
                              items: TaskPriority.values.map((TaskPriority priority) {
                                return DropdownMenuItem<TaskPriority>(
                                  value: priority,
                                  child:
                                      Text(priority.toString().split('.').last),
                                );
                              }).toList(),
                              onChanged: (newValue) {
                                setState(() {
                                  priority = newValue!;
                                });
                              },
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Annuler'),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () {
                                    if (addFormKey.currentState!.validate()) {
                                      addFormKey.currentState!.save();
                                      _addTask(
                                        addFormKey,
                                        title,
                                        description,
                                        dueDate,
                                        assignee,
                                        status,
                                        priority,
                                      );
                                    }
                                  },
                                  child: const Text('Ajouter'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// Méthode pour afficher le formulaire de modification de tâche
  void _showEditTaskDialog(Task task) {
    bool assigneeExists = _users.any((user) => user.uid == task.assignee);

    String title = task.title;
    String description = task.description;
    DateTime dueDate = task.dueDate;
    String assignee = assigneeExists ? task.assignee : '';
    TaskStatus status = task.status;
    TaskPriority priority = task.priority;

    final GlobalKey<FormState> editFormKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                // On prépare les items pour l'assignation
                List<DropdownMenuItem<String>> assigneeItems = [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('Non Assigné'),
                  ),
                  ..._users
                      .where((user) => user.uid.isNotEmpty)
                      .map((UserModel user) {
                    return DropdownMenuItem<String>(
                      value: user.uid,
                      child: Text(user.displayName),
                    );
                  }),
                ];

                // Forcer à '' si l'assignee n'est pas trouvé
                if (assignee.isNotEmpty &&
                    !assigneeItems.any((item) => item.value == assignee)) {
                  assignee = '';
                }

                return SingleChildScrollView(
                  child: Column(
                    children: [
                      Text(
                        'Modifier la Tâche',
                        style: GoogleFonts.lato(
                          textStyle: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Form(
                        key: editFormKey,
                        child: Column(
                          children: [
                            TextFormField(
                              initialValue: title,
                              decoration: const InputDecoration(
                                labelText: 'Titre',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Veuillez entrer un titre';
                                }
                                return null;
                              },
                              onSaved: (value) => title = value!,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              initialValue: description,
                              decoration: const InputDecoration(
                                labelText: 'Description',
                                border: OutlineInputBorder(),
                              ),
                              maxLines: 3,
                              onSaved: (value) => description = value ?? '',
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.calendar_today,
                                    color: Colors.blue),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat('dd/MM/yyyy').format(dueDate),
                                  style: GoogleFonts.lato(fontSize: 16),
                                ),
                                const Spacer(),
                                ElevatedButton(
                                  onPressed: () async {
                                    DateTime? picked = await showDatePicker(
                                      context: context,
                                      initialDate: dueDate,
                                      firstDate: DateTime.now(),
                                      lastDate: DateTime(2100),
                                    );
                                    if (picked != null && picked != dueDate) {
                                      setState(() {
                                        dueDate = picked;
                                      });
                                    }
                                  },
                                  child: const Text('Changer'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Assigné à',
                                border: OutlineInputBorder(),
                              ),
                              value: assigneeItems
                                      .any((item) => item.value == assignee)
                                  ? assignee
                                  : '',
                              items: assigneeItems,
                              onChanged: (newValue) {
                                setState(() {
                                  assignee = newValue ?? '';
                                });
                              },
                              onSaved: (value) => assignee = value ?? '',
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<TaskStatus>(
                              decoration: const InputDecoration(
                                labelText: 'Statut',
                                border: OutlineInputBorder(),
                              ),
                              value: status,
                              items: TaskStatus.values.map((TaskStatus status) {
                                return DropdownMenuItem<TaskStatus>(
                                  value: status,
                                  child: Text(status.toString().split('.').last),
                                );
                              }).toList(),
                              onChanged: (newValue) {
                                setState(() {
                                  status = newValue!;
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<TaskPriority>(
                              decoration: const InputDecoration(
                                labelText: 'Priorité',
                                border: OutlineInputBorder(),
                              ),
                              value: priority,
                              items: TaskPriority.values.map((TaskPriority priority) {
                                return DropdownMenuItem<TaskPriority>(
                                  value: priority,
                                  child: Text(priority.toString().split('.').last),
                                );
                              }).toList(),
                              onChanged: (newValue) {
                                setState(() {
                                  priority = newValue!;
                                });
                              },
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(),
                                  child: const Text('Annuler'),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () => _updateTask(
                                    editFormKey,
                                    task,
                                    title,
                                    description,
                                    dueDate,
                                    assignee,
                                    status,
                                    priority,
                                  ),
                                  child: const Text('Enregistrer'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des Tâches'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CalendarPage()),
              ).then((_) {
                _fetchUsers();
              });
            },
            tooltip: 'Voir le Calendrier',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Déconnecté avec succès.')),
              );
            },
            tooltip: 'Se Déconnecter',
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTaskDialog,
        label: const Text('Ajouter une Tâche'),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.blue,
      ),
    );
  }
}
