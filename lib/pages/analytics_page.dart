// lib/pages/analytics_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart'; // Import nécessaire pour DateFormat
import '../models/task.dart';
import '../widgets/auth_guard.dart'; // Si vous souhaitez sécuriser la page

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({Key? key}) : super(key: key);

  @override
  _AnalyticsPageState createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Variables pour stocker les statistiques
  int _totalTasks = 0;
  Map<TaskStatus, int> _statusCount = {};
  Map<TaskPriority, int> _priorityCount = {};

  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchTaskStatistics();
  }

  Future<void> _fetchTaskStatistics() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Utilisateur non authentifié.';
        });
        return;
      }

      // Récupérer toutes les tâches de l'utilisateur
      QuerySnapshot snapshot = await _firestore
          .collection('tasks')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      List<Task> tasks = snapshot.docs.map((doc) => Task.fromFirestore(doc)).toList();

      // Calculer les statistiques
      int total = tasks.length;
      Map<TaskStatus, int> statusMap = {};
      Map<TaskPriority, int> priorityMap = {};

      for (var task in tasks) {
        // Compter les statuts
        statusMap[task.status] = (statusMap[task.status] ?? 0) + 1;

        // Compter les priorités
        priorityMap[task.priority] = (priorityMap[task.priority] ?? 0) + 1;
      }

      setState(() {
        _totalTasks = total;
        _statusCount = statusMap;
        _priorityCount = priorityMap;
        _isLoading = false;
      });
    } catch (e) {
      print('Erreur lors de la récupération des statistiques: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Erreur lors de la récupération des statistiques.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Analytics',
          style: GoogleFonts.roboto(),
        ),
        backgroundColor: Colors.grey[800],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Text(
                    _errorMessage,
                    style: TextStyle(color: Colors.red, fontSize: 16),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Statistiques Générales
                      Text(
                        'Statistiques Générales',
                        style: GoogleFonts.roboto(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 10),
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        color: Colors.white,
                        child: ListTile(
                          leading: Icon(Icons.assignment, color: Colors.blueAccent, size: 40),
                          title: Text(
                            'Total des Tâches',
                            style: GoogleFonts.roboto(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          trailing: Text(
                            '$_totalTasks',
                            style: GoogleFonts.roboto(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueAccent,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 20),

                      // Répartition des Statuts
                      Text(
                        'Répartition des Statuts',
                        style: GoogleFonts.roboto(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 10),
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              // Ajout d'une contrainte de taille
                              SizedBox(
                                height: 200,
                                child: PieChart(
                                  PieChartData(
                                    sections: _statusCount.entries.map((entry) {
                                      double percentage = (_totalTasks > 0)
                                          ? (entry.value / _totalTasks) * 100
                                          : 0;
                                      return PieChartSectionData(
                                        color: _getStatusColor(entry.key),
                                        value: entry.value.toDouble(),
                                        title: '${percentage.toStringAsFixed(1)}%',
                                        radius: 50,
                                        titleStyle: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      );
                                    }).toList(),
                                    sectionsSpace: 2,
                                    centerSpaceRadius: 40,
                                  ),
                                ),
                              ),
                              SizedBox(height: 10),
                              Column(
                                children: _statusCount.entries.map((entry) {
                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 16,
                                        height: 16,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _getStatusColor(entry.key),
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        '${entry.key.toString().split('.').last} (${entry.value})',
                                        style: GoogleFonts.roboto(fontSize: 14),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 20),

                      // Répartition des Priorités
                      Text(
                        'Répartition des Priorités',
                        style: GoogleFonts.roboto(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 10),
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              // Ajout d'une contrainte de taille
                              SizedBox(
                                height: 200,
                                child: BarChart(
                                  BarChartData(
                                    alignment: BarChartAlignment.spaceAround,
                                    maxY: (_priorityCount.values.isNotEmpty)
                                        ? _priorityCount.values.reduce((a, b) => a > b ? a : b).toDouble() + 1
                                        : 5,
                                    barTouchData: BarTouchData(enabled: false),
                                    titlesData: FlTitlesData(
                                      show: true,
                                      leftTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          getTitlesWidget: (value, meta) {
                                            return Text(
                                              value.toInt().toString(),
                                              style: TextStyle(
                                                color: Colors.black54,
                                                fontSize: 12,
                                              ),
                                            );
                                          },
                                          reservedSize: 30,
                                          interval: 1,
                                        ),
                                      ),
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          getTitlesWidget: (double value, TitleMeta meta) {
                                            switch (value.toInt()) {
                                              case 0:
                                                return Text('Low');
                                              case 1:
                                                return Text('Medium');
                                              case 2:
                                                return Text('High');
                                              default:
                                                return SizedBox.shrink();
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                    borderData: FlBorderData(show: false),
                                    barGroups: [
                                      BarChartGroupData(
                                        x: 0,
                                        barRods: [
                                          BarChartRodData(
                                            toY: _priorityCount[TaskPriority.Low]?.toDouble() ?? 0,
                                            color: Colors.green, // Correction de 'colors' à 'color'
                                            width: 20,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                        ],
                                      ),
                                      BarChartGroupData(
                                        x: 1,
                                        barRods: [
                                          BarChartRodData(
                                            toY: _priorityCount[TaskPriority.Medium]?.toDouble() ?? 0,
                                            color: Colors.orange, // Correction de 'colors' à 'color'
                                            width: 20,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                        ],
                                      ),
                                      BarChartGroupData(
                                        x: 2,
                                        barRods: [
                                          BarChartRodData(
                                            toY: _priorityCount[TaskPriority.High]?.toDouble() ?? 0,
                                            color: Colors.red, // Correction de 'colors' à 'color'
                                            width: 20,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  _buildPriorityLegend(Colors.green, 'Low'),
                                  SizedBox(width: 16),
                                  _buildPriorityLegend(Colors.orange, 'Medium'),
                                  SizedBox(width: 16),
                                  _buildPriorityLegend(Colors.red, 'High'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 20),

                      // Graphique des Tâches par Mois
                      Text(
                        'Tâches par Mois',
                        style: GoogleFonts.roboto(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 10),
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: FutureBuilder<Map<String, int>>(
                            future: _getTasksPerMonth(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return Center(child: CircularProgressIndicator());
                              }

                              if (snapshot.hasError) {
                                return Center(
                                  child: Text(
                                    'Erreur: ${snapshot.error}',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                );
                              }

                              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                                return Center(
                                  child: Text(
                                    'Aucune donnée disponible.',
                                    style: GoogleFonts.roboto(
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                );
                              }

                              Map<String, int> tasksPerMonth = snapshot.data!;

                              return Column(
                                children: [
                                  SizedBox(
                                    height: 200,
                                    child: BarChart(
                                      BarChartData(
                                        alignment: BarChartAlignment.spaceAround,
                                        maxY: tasksPerMonth.values.reduce((a, b) => a > b ? a : b).toDouble() + 1,
                                        barTouchData: BarTouchData(enabled: false),
                                        titlesData: FlTitlesData(
                                          show: true,
                                          leftTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: true,
                                              getTitlesWidget: (value, meta) {
                                                return Text(
                                                  value.toInt().toString(),
                                                  style: TextStyle(
                                                    color: Colors.black54,
                                                    fontSize: 12,
                                                  ),
                                                );
                                              },
                                              reservedSize: 30,
                                              interval: 1,
                                            ),
                                          ),
                                          bottomTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: true,
                                              getTitlesWidget: (double value, TitleMeta meta) {
                                                int index = value.toInt();
                                                if (index >= 0 && index < tasksPerMonth.keys.length) {
                                                  return Text(tasksPerMonth.keys.elementAt(index));
                                                }
                                                return SizedBox.shrink();
                                              },
                                            ),
                                          ),
                                        ),
                                        borderData: FlBorderData(show: false),
                                        barGroups: List.generate(tasksPerMonth.length, (index) {
                                          String month = tasksPerMonth.keys.elementAt(index);
                                          int count = tasksPerMonth[month]!;
                                          return BarChartGroupData(
                                            x: index,
                                            barRods: [
                                              BarChartRodData(
                                                toY: count.toDouble(),
                                                color: Colors.blue, // Correction de 'colors' à 'color'
                                                width: 20,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                            ],
                                          );
                                        }),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  /// Méthode pour construire la légende des priorités
  Widget _buildPriorityLegend(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        SizedBox(width: 4),
        Text(label, style: GoogleFonts.roboto(fontSize: 14)),
      ],
    );
  }

  /// Méthode pour récupérer les tâches par mois
  Future<Map<String, int>> _getTasksPerMonth() async {
    User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      return {};
    }

    QuerySnapshot snapshot = await _firestore
        .collection('tasks')
        .where('userId', isEqualTo: currentUser.uid)
        .get();

    List<Task> tasks = snapshot.docs.map((doc) => Task.fromFirestore(doc)).toList();

    Map<String, int> tasksPerMonth = {};

    for (var task in tasks) {
      String month = DateFormat('MMM yyyy').format(task.dueDate);
      tasksPerMonth[month] = (tasksPerMonth[month] ?? 0) + 1;
    }

    // Trier les mois par date croissante
    var sortedKeys = tasksPerMonth.keys.toList()
      ..sort((a, b) {
        DateTime dateA = DateFormat('MMM yyyy').parse(a);
        DateTime dateB = DateFormat('MMM yyyy').parse(b);
        return dateA.compareTo(dateB);
      });

    Map<String, int> sortedTasksPerMonth = {};
    for (var key in sortedKeys) {
      sortedTasksPerMonth[key] = tasksPerMonth[key]!;
    }

    return sortedTasksPerMonth;
  }

  /// Méthode pour obtenir la couleur correspondant au statut d'une tâche
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

  /// Méthode pour obtenir la couleur correspondant à la priorité d'une tâche
  Color _getPriorityColor(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.Low:
        return Colors.green;
      case TaskPriority.Medium:
        return Colors.orange;
      case TaskPriority.High:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
