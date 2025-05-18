import 'package:firebase_web_app/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart'; // Ajout pour la prise en charge des mois en français
import '../models/task.dart';
import 'package:provider/provider.dart';

// Extension pour traduire les statuts des tâches en français
extension TaskStatusFrench on TaskStatus {
  String get frenchName {
    switch (this) {
      case TaskStatus.PendingValidation:
        return 'En Attente de Validation';
      case TaskStatus.ToDo:
        return 'À Faire';
      case TaskStatus.InProgress:
        return 'En Cours';
      case TaskStatus.Done:
        return 'Terminé';
      case TaskStatus.Pending:
      default:
        return 'En Attente';
    }
  }
}

class AnalyticsPage extends StatefulWidget {
  final String workspaceId;

  const AnalyticsPage({Key? key, required this.workspaceId}) : super(key: key);

  @override
  _AnalyticsPageState createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  int _totalTasks = 0;
  Map<TaskStatus, int> _statusCount = {};
  Map<TaskPriority, int> _priorityCount = {};

  double _totalRevenueTTC = 0.0;
  double _billedRevenue = 0.0;
  double _unbilledRevenue = 0.0;
  double _revenueCurrentMonth2025 = 0.0;
  double _revenueLastMonth = 0.0;
  double _revenueCurrentYear = 0.0;

  int _openFolders = 0;
  int _closedFolders = 0;
  int _folderCreationsCurrentMonth2025 = 0;
  int _folderCreationsLastMonth = 0;
  int _folderCreationsCurrentYear = 0;

  Map<String, double> _revenuePerDayLast7Days = {};
  Map<String, double> _revenuePerDayLast28Days = {};
  Map<String, double> _revenuePerMonthCurrentYear = {};

  List<Map<String, dynamic>> _folders = [];
  List<Task> _tasks = [];

  bool _isLoading = true;
  String _errorMessage = '';
  int? _hoveredFolderIndex;
  String? _searchQuery;
  bool _sortAscending = true;
  String _sortColumn = 'name';

  DateTime? _startDate;

  @override
  void initState() {
    super.initState();
    debugPrint("Initialisation de la page d'analyse avec workspaceId: ${widget.workspaceId}");
    _fetchFinancialStatistics();

    User? currentUser = _auth.currentUser;
    if (currentUser != null) {
      _firestore
          .collection('workspaces')
          .doc(widget.workspaceId)
          .collection('tasks')
          .where('assignee', isEqualTo: currentUser.uid)
          .snapshots()
          .listen((snapshot) {
        final List<Task> tasksList = snapshot.docs.map((doc) => Task.fromFirestore(doc)).toList();
        if (mounted) {
          setState(() {
            _tasks = tasksList;
            _totalTasks = _tasks.length;
            _updateTaskStatistics(_tasks);
            _isLoading = false;
          });
        }
      }, onError: (e) {
        debugPrint('Erreur lors de l’écoute des tâches: $e');
        if (mounted) {
          setState(() {
            _errorMessage = 'Erreur lors de la récupération des tâches: $e';
            _isLoading = false;
          });
        }
      });
    } else {
      setState(() {
        _errorMessage = 'Utilisateur non authentifié.';
        _isLoading = false;
      });
    }
  }

  void _updateTaskStatistics(List<Task> tasks) {
    Map<TaskStatus, int> statusMap = {};
    Map<TaskPriority, int> priorityMap = {};

    for (var task in tasks) {
      statusMap[task.status] = (statusMap[task.status] ?? 0) + 1;
      priorityMap[task.priority] = (priorityMap[task.priority] ?? 0) + 1;
    }

    _statusCount = statusMap;
    _priorityCount = priorityMap;
  }

  Future<void> _fetchFinancialStatistics() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Utilisateur non authentifié.';
        });
        return;
      }

      debugPrint("Début de la récupération des statistiques financières pour workspaceId: ${widget.workspaceId}");
      QuerySnapshot folderSnapshot = await _firestore
          .collection('workspaces')
          .doc(widget.workspaceId)
          .collection('folders')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      double totalRevenue = 0.0;
      double billed = 0.0;
      double unbilled = 0.0;
      int openFolders = 0;
      int closedFolders = 0;
      double revenueCurrentMonth2025 = 0.0;
      double revenueLastMonth = 0.0;
      double revenueCurrentYear = 0.0;
      int folderCreationsCurrentMonth2025 = 0;
      int folderCreationsLastMonth = 0;
      int folderCreationsCurrentYear = 0;

      Map<String, double> revenuePerDayLast7Days = {};
      Map<String, double> revenuePerDayLast28Days = {};
      Map<String, double> revenuePerMonthCurrentYear = {};
      List<Map<String, dynamic>> foldersList = [];
      DateTime? earliestDate;

      DateTime now = DateTime.now();
      DateTime today = DateTime(now.year, now.month, now.day);
      DateTime currentMonthStart = DateTime(now.year, now.month, 1);
      DateTime lastMonthStart = DateTime(now.year, now.month - 1, 1);
      DateTime currentYearStart = DateTime(now.year, 1, 1);

      // Initialisation des 7 derniers jours (lundi à dimanche)
      DateTime startOfWeek = today.subtract(Duration(days: today.weekday - 1)); // Lundi de la semaine en cours
      for (int i = 0; i < 7; i++) {
        DateTime day = startOfWeek.add(Duration(days: i));
        String dayKey = DateFormat('yyyy-MM-dd').format(day);
        revenuePerDayLast7Days[dayKey] = 0.0; // Initialisation à 0
      }

      // Initialisation des 28 derniers jours (4 semaines)
      DateTime startOfLast28Days = today.subtract(const Duration(days: 27)); // 28 jours complets
      for (int i = 0; i < 28; i++) {
        DateTime day = startOfLast28Days.add(Duration(days: i));
        String dayKey = DateFormat('yyyy-MM-dd').format(day);
        revenuePerDayLast28Days[dayKey] = 0.0; // Initialisation à 0
      }

      // Initialisation des mois de l'année 2025
      for (int month = 1; month <= 12; month++) {
        String monthKey = DateFormat('yyyy-MM').format(DateTime(2025, month));
        revenuePerMonthCurrentYear[monthKey] = 0.0; // Initialisation à 0
      }

      for (var folderDoc in folderSnapshot.docs) {
        Map<String, dynamic> folderData = folderDoc.data() as Map<String, dynamic>;
        Map<String, String>? folderMapping = folderData['folderMapping'] != null
            ? Map<String, String>.from(folderData['folderMapping'])
            : null;
        Timestamp? timestamp = folderData['timestamp'] as Timestamp?;
        Timestamp? closedAt = folderData['closedAt'] as Timestamp?;
        bool isClosed = folderData['isClosed'] ?? false;

        double ttcValue = 0.0;
        if (folderMapping != null && folderMapping.containsKey('total ttc')) {
          ttcValue = double.tryParse(folderMapping['total ttc'] ?? '0') ?? 0.0;
          totalRevenue += ttcValue;

          if (isClosed && closedAt != null) {
            DateTime closeDate = closedAt.toDate();
            if (earliestDate == null || closeDate.isBefore(earliestDate)) {
              earliestDate = closeDate;
            }

            // Revenus des 7 derniers jours
            if (closeDate.isAfter(startOfWeek.subtract(Duration(days: 1)))) {
              String dayKey = DateFormat('yyyy-MM-dd').format(closeDate);
              revenuePerDayLast7Days[dayKey] = (revenuePerDayLast7Days[dayKey] ?? 0) + ttcValue;
            }

            // Revenus des 28 derniers jours
            if (closeDate.isAfter(startOfLast28Days.subtract(Duration(days: 1)))) {
              String dayKey = DateFormat('yyyy-MM-dd').format(closeDate);
              revenuePerDayLast28Days[dayKey] = (revenuePerDayLast28Days[dayKey] ?? 0) + ttcValue;
            }

            // Revenus par mois de l'année 2025
            if (closeDate.year == 2025) {
              String monthKey = DateFormat('yyyy-MM').format(closeDate);
              revenuePerMonthCurrentYear[monthKey] = (revenuePerMonthCurrentYear[monthKey] ?? 0) + ttcValue;
            }

            if (closeDate.year == 2025 && closeDate.month == now.month) {
              revenueCurrentMonth2025 += ttcValue;
            }
            if (closeDate.year == now.year && closeDate.month == now.month - 1) {
              revenueLastMonth += ttcValue;
            }
            if (closeDate.year == now.year) {
              revenueCurrentYear += ttcValue;
            }

            billed += ttcValue;
            closedFolders++;
          } else {
            unbilled += ttcValue;
            openFolders++;
          }
        }

        if (timestamp != null) {
          DateTime creationDate = timestamp.toDate();
          if (creationDate.year == 2025 && creationDate.month == now.month) {
            folderCreationsCurrentMonth2025++;
          }
          if (creationDate.year == now.year && creationDate.month == now.month - 1) {
            folderCreationsLastMonth++;
          }
          if (creationDate.year == now.year) {
            folderCreationsCurrentYear++;
          }
        }

        foldersList.add({
          'id': folderDoc.id,
          'name': folderData['name'] ?? 'Sans nom',
          'totalTTC': ttcValue,
          'isClosed': isClosed,
          'timestamp': timestamp?.toDate(),
          'closedAt': closedAt?.toDate(),
        });
      }

      if (mounted) {
        setState(() {
          _startDate = earliestDate ?? DateTime.now();
          _totalRevenueTTC = totalRevenue;
          _billedRevenue = billed;
          _unbilledRevenue = unbilled;
          _openFolders = openFolders;
          _closedFolders = closedFolders;
          _revenuePerDayLast7Days = revenuePerDayLast7Days;
          _revenuePerDayLast28Days = revenuePerDayLast28Days;
          _revenuePerMonthCurrentYear = revenuePerMonthCurrentYear;
          _revenueCurrentMonth2025 = revenueCurrentMonth2025;
          _revenueLastMonth = revenueLastMonth;
          _revenueCurrentYear = revenueCurrentYear;
          _folderCreationsCurrentMonth2025 = folderCreationsCurrentMonth2025;
          _folderCreationsLastMonth = folderCreationsLastMonth;
          _folderCreationsCurrentYear = folderCreationsCurrentYear;
          _folders = foldersList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erreur lors de la récupération des statistiques financières: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Erreur lors de la récupération des statistiques financières: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleFolderStatus(String folderId, bool currentStatus) async {
    try {
      setState(() {
        _isLoading = true;
      });

      DateTime now = DateTime.now();
      await _firestore
          .collection('workspaces')
          .doc(widget.workspaceId)
          .collection('folders')
          .doc(folderId)
          .update({
        'isClosed': !currentStatus,
        'closedAt': !currentStatus ? Timestamp.fromDate(now) : FieldValue.delete(),
      });

      await _fetchFinancialStatistics();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(currentStatus ? 'Dossier rouvert' : 'Dossier clos')),
      );
    } catch (e) {
      debugPrint('Erreur lors de la mise à jour du statut: $e');
      setState(() {
        _errorMessage = 'Erreur lors de la mise à jour du statut: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la mise à jour du statut: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showFolderDetails(Map<String, dynamic> folder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          folder['name'],
          style: GoogleFonts.roboto(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total TTC: ${folder['totalTTC'].toStringAsFixed(2)} €', style: GoogleFonts.roboto(fontSize: 12)),
            Text('Statut: ${folder['isClosed'] ? "Clos" : "Ouvert"}', style: GoogleFonts.roboto(fontSize: 12)),
            if (folder['timestamp'] != null)
              Text('Ouvert le: ${DateFormat.yMMMMd('fr_FR').format(folder['timestamp'])}', style: GoogleFonts.roboto(fontSize: 12)),
            if (folder['closedAt'] != null)
              Text('Fermé le: ${DateFormat.yMMMMd('fr_FR').format(folder['closedAt'])}', style: GoogleFonts.roboto(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Fermer', style: GoogleFonts.roboto(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _showTaskDetails(Task task) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(task.title),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Description: ${task.description}'),
                const SizedBox(height: 6),
                Text('Date d’échéance: ${DateFormat('dd/MM/yyyy', 'fr_FR').format(task.dueDate)}'),
                const SizedBox(height: 6),
                Text('Durée: ${task.duration} minutes'),
                const SizedBox(height: 6),
                Text('Assigné à: ${task.assigneeName}'),
                const SizedBox(height: 6),
                Text('Priorité: ${task.priority.toString().split('.').last}'),
                const SizedBox(height: 6),
                Text('Statut: ${task.status.frenchName}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Fermer'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTasksSection() {
    List<Task> tasks = _tasks.where((task) => task.status != TaskStatus.Done).toList();
    tasks.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    tasks = tasks.take(20).toList();

    return Card(
      elevation: 2,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        height: 300,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tâches Actives',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/suivi_taches',
                          arguments: {'workspaceId': widget.workspaceId});
                    },
                    child: Text(
                      'Voir Tout',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Text(
                        'Aucune tâche active',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: tasks.length,
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        return Card(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          elevation: 1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.title,
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  task.description,
                                  style: Theme.of(context).textTheme.bodySmall,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'À faire le ${DateFormat('dd/MM/yyyy', 'fr_FR').format(task.dueDate)}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(task.status),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        task.status.frenchName,
                                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                              color: Theme.of(context).colorScheme.onPrimary,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.bottomRight,
                                  child: ElevatedButton(
                                    onPressed: () => _showTaskDetails(task),
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(60, 28),
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                    ),
                                    child: Text(
                                      'Détails',
                                      style: Theme.of(context).textTheme.labelSmall,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(TaskStatus status) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final brightness = themeProvider.isDarkMode ? Brightness.dark : Brightness.light;

    switch (status) {
      case TaskStatus.PendingValidation:
        return Theme.of(context).colorScheme.tertiary;
      case TaskStatus.ToDo:
        return Theme.of(context).colorScheme.primary;
      case TaskStatus.InProgress:
        return Theme.of(context).colorScheme.secondary;
      case TaskStatus.Done:
        return Theme.of(context).colorScheme.primaryContainer;
      case TaskStatus.Pending:
      default:
        return Theme.of(context).disabledColor;
    }
  }

  DateTime _parseKey(String key) {
    if (key.length == 7) { // Format 'yyyy-MM'
      return DateTime.parse(key + '-01');
    } else if (key.length == 10) { // Format 'yyyy-MM-dd'
      return DateTime.parse(key);
    } else {
      throw FormatException('Clé de date invalide: $key');
    }
  }

  Widget _buildRevenueChart({
    required BuildContext context,
    required String title,
    required Map<String, double> revenueData,
    required String dateFormat,
    bool isWeekRange = false,
    bool isYearly = false,
  }) {
    List<String> sortedKeys = revenueData.keys.toList()
      ..sort((a, b) {
        DateTime dateA = _parseKey(a);
        DateTime dateB = _parseKey(b);
        return dateA.compareTo(dateB);
      });

    // Créer une liste initiale de points
    List<FlSpot> spots = [];
    double maxRevenue = 0;

    for (int i = 0; i < sortedKeys.length; i++) {
      double revenue = revenueData[sortedKeys[i]]!;
      if (revenue < 0) revenue = 0; // Forcer les valeurs négatives à 0
      spots.add(FlSpot(i.toDouble(), revenue));
      if (revenue > maxRevenue) maxRevenue = revenue;
    }

    if (spots.isEmpty || maxRevenue == 0) {
      return Card(
        elevation: 2,
        color: Theme.of(context).cardColor,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Center(
            child: Text('Aucun revenu pour $title'),
          ),
        ),
      );
    }

    // Définir minY comme un pourcentage négatif de maxRevenue (10%)
    double minY = -maxRevenue * 0.1;
    if (minY > 0) minY = 0; // Assurer que minY ne devient pas positif

    return Card(
      elevation: 2,
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: maxRevenue / 4, // Utiliser uniquement la partie positive pour les étiquettes
                        getTitlesWidget: (value, meta) {
                          if (value < 0) return const SizedBox.shrink(); // Masquer les valeurs négatives
                          return Text(
                            value.toStringAsFixed(0),
                            style: const TextStyle(fontSize: 12),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          int index = value.toInt();
                          if (index >= 0 && index < sortedKeys.length) {
                            String label = sortedKeys[index];
                            DateTime date = _parseKey(label);
                            if (title.contains('7 Derniers Jours')) {
                              return Text(
                                DateFormat('EEE', 'fr_FR').format(date), // "Lun", "Mar", etc.
                                style: const TextStyle(fontSize: 10),
                                overflow: TextOverflow.ellipsis,
                              );
                            } else if (isWeekRange) {
                              return Text(
                                date.day.toString(),
                                style: const TextStyle(fontSize: 10),
                                overflow: TextOverflow.ellipsis,
                              );
                            } else if (isYearly) {
                              return Text(
                                DateFormat('MMM', 'fr_FR').format(date), // "Jan", "Fév", etc.
                                style: const TextStyle(fontSize: 10),
                                overflow: TextOverflow.ellipsis,
                              );
                            } else {
                              return Text(
                                DateFormat(dateFormat, 'fr_FR').format(date),
                                style: const TextStyle(fontSize: 10),
                                overflow: TextOverflow.ellipsis,
                              );
                            }
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true),
                  minX: 0,
                  maxX: (sortedKeys.length - 1).toDouble(),
                  minY: minY, // Conserver minY négatif pour la spline
                  maxY: maxRevenue * 1.2,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true, // Conserver l'effet spline
                      color: Theme.of(context).colorScheme.primary,
                      barWidth: 3,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(show: false),
                      curveSmoothness: 0.35, // Ajuster la tension pour réduire les oscillations
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Analyse',
          style: GoogleFonts.roboto(
            color: Theme.of(context).appBarTheme.titleTextStyle?.color,
            fontSize: 16,
          ),
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 2,
        iconTheme: Theme.of(context).iconTheme,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Text(
                    _errorMessage,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      fit: FlexFit.loose,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionTitle('Dossiers & Statistiques'),
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.5,
                              child: _buildFolderList(),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildStatCard('Tâches', '$_totalTasks', Icons.assignment),
                                _buildStatCard('Total TTC', '${_totalRevenueTTC.toStringAsFixed(2)} €', Icons.attach_money),
                                _buildStatCard('Facturé', '${_billedRevenue.toStringAsFixed(2)} €', Icons.check_circle),
                                _buildStatCard('Non facturé', '${_unbilledRevenue.toStringAsFixed(2)} €', Icons.pending),
                                _buildStatCard('Ouverts', '$_openFolders', Icons.folder_open),
                                _buildStatCard('Fermés', '$_closedFolders', Icons.folder),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildSectionTitle('Statuts des Tâches'),
                            _buildStatusPieChart(),
                            const SizedBox(height: 12),
                            _buildSectionTitle('Tâches Actives'),
                            _buildTasksSection(),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionTitle('Créations et Revenus'),
                            Row(
                              children: [
                                Expanded(
                                  flex: 1,
                                  child: _buildFolderCreationsStats(),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: _buildRevenueVariationStats(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildSectionTitle('Revenus Facturés'),
                            _buildRevenueChart(
                              context: context,
                              title: '7 Derniers Jours',
                              revenueData: _revenuePerDayLast7Days,
                              dateFormat: 'EEE',
                            ),
                            const SizedBox(height: 12),
                            _buildRevenueChart(
                              context: context,
                              title: '4 Dernières Semaines',
                              revenueData: _revenuePerDayLast28Days,
                              dateFormat: 'd',
                              isWeekRange: true,
                            ),
                            const SizedBox(height: 12),
                            _buildRevenueChart(
                              context: context,
                              title: 'Année 2025 (par mois)',
                              revenueData: _revenuePerMonthCurrentYear,
                              dateFormat: 'MMM',
                              isYearly: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

Widget _buildStatCard(String title, String value, IconData icon) {
  return Expanded(
    child: Card(
      elevation: 2,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(
              icon,
              size: 28,
              color: Colors.grey[600], // Changement ici : icônes en gris
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildFolderList() {
    List<Map<String, dynamic>> filteredFolders = _folders.where((folder) {
      if (_searchQuery == null || _searchQuery!.isEmpty) return true;
      final query = _searchQuery!.toLowerCase();
      return folder['name'].toLowerCase().contains(query) ||
          (folder['totalTTC'].toString().contains(query)) ||
          (folder['isClosed'] ? 'Clos' : 'Ouvert').toLowerCase().contains(query);
    }).toList();

    filteredFolders.sort((a, b) {
      final aValue = _sortColumn == 'name' ? a['name'] : (a['isClosed'] ? 'Clos' : 'Ouvert');
      final bValue = _sortColumn == 'name' ? b['name'] : (b['isClosed'] ? 'Clos' : 'Ouvert');
      return _sortAscending
          ? aValue.toString().compareTo(bValue.toString())
          : bValue.toString().compareTo(aValue.toString());
    });

    return Card(
      elevation: 2,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Rechercher un dossier...',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                flex: 1,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _sortColumn = 'name';
                      _sortAscending = !_sortAscending;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Nom',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _sortColumn = 'status';
                      _sortAscending = !_sortAscending;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Statut',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 80),
            ],
          ),
          Flexible(
            fit: FlexFit.loose,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: filteredFolders.length,
              itemBuilder: (context, index) {
                final folder = filteredFolders[index];
                return MouseRegion(
                  onEnter: (_) => setState(() => _hoveredFolderIndex = index),
                  onExit: (_) => setState(() => _hoveredFolderIndex = null),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(8.0),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: folder['isClosed'] ? Colors.green[300] : Theme.of(context).colorScheme.primary,
                      child: Text(
                        folder['name'][0].toUpperCase(),
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                      ),
                    ),
                    title: Text(
                      folder['name'],
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    subtitle: Text(
                      'TTC: ${folder['totalTTC'].toStringAsFixed(2)} € - ${folder['isClosed'] ? "Clos" : "Ouvert"}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            folder['isClosed'] ? Icons.lock_open : Icons.lock,
                            color: _hoveredFolderIndex == index ? Theme.of(context).colorScheme.primary : Theme.of(context).iconTheme.color,
                            size: 20,
                          ),
                          onPressed: () => _toggleFolderStatus(folder['id'], folder['isClosed']),
                          tooltip: folder['isClosed'] ? 'Rouvrir' : 'Clore',
                          padding: EdgeInsets.zero,
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.info_outline,
                            color: _hoveredFolderIndex == index ? Theme.of(context).colorScheme.primary : Theme.of(context).iconTheme.color,
                            size: 20,
                          ),
                          onPressed: () => _showFolderDetails(folder),
                          tooltip: 'Détails',
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (filteredFolders.isEmpty)
            Expanded(
              child: Container(
                color: Colors.transparent,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusPieChart() {
    return Card(
      elevation: 2,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 150,
              child: _statusCount.isEmpty
                  ? Center(
                      child: Text(
                        'Aucune tâche',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : PieChart(
                      PieChartData(
                        sections: _statusCount.entries.map((entry) {
                          double percentage = (_totalTasks > 0) ? (entry.value / _totalTasks) * 100 : 0;
                          return PieChartSectionData(
                            color: _getStatusColor(entry.key),
                            value: entry.value.toDouble(),
                            title: '${percentage.toStringAsFixed(0)}%',
                            radius: 40,
                            titleStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).cardColor,
                            ),
                          );
                        }).toList(),
                        sectionsSpace: 2,
                        centerSpaceRadius: 30,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            _statusCount.isEmpty
                ? const SizedBox.shrink()
                : Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _statusCount.entries.map((entry) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _getStatusColor(entry.key),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${entry.key.frenchName} (${entry.value})',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      );
                    }).toList(),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderCreationsStats() {
    List<String> periods = ['Mois 2025', 'Mois précédent', 'Année 2025'];
    List<int> creations = [
      _folderCreationsCurrentMonth2025,
      _folderCreationsLastMonth,
      _folderCreationsCurrentYear,
    ];
    List<int> comparisons = [
      _folderCreationsLastMonth,
      0,
      0,
    ];

    return Card(
      elevation: 2,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Créations de Dossiers'),
            const SizedBox(height: 8),
            if (creations.every((creation) => creation == 0))
              Center(
                child: Text(
                  'Aucune création',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              Column(
                children: List.generate(periods.length, (index) {
                  double? percentageChange;
                  String? indicator;
                  if (index == 0 && comparisons[index] > 0) {
                    percentageChange = _calculatePercentageChange(creations[index].toDouble(), comparisons[index].toDouble());
                    indicator = _getVariationIndicator(creations[index].toDouble(), comparisons[index].toDouble());
                  }
                  return _buildStatLine(
                    periods[index],
                    creations[index].toString(),
                    percentageChange,
                    indicator,
                  );
                }),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueVariationStats() {
    List<String> periods = ['Mois 2025', 'Mois précédent', 'Année 2025'];
    List<double> revenues = [
      _revenueCurrentMonth2025,
      _revenueLastMonth,
      _revenueCurrentYear,
    ];
    List<double> comparisons = [
      _revenueLastMonth,
      0,
      0,
    ];

    return Card(
      elevation: 2,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Chiffre d\'Affaires (CA)'),
            const SizedBox(height: 8),
            if (revenues.every((revenue) => revenue == 0))
              Center(
                child: Text(
                  'Aucun CA',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              Column(
                children: List.generate(periods.length, (index) {
                  double? percentageChange;
                  String? indicator;
                  if (index == 0 && comparisons[index] > 0) {
                    percentageChange = _calculatePercentageChange(revenues[index], comparisons[index]);
                    indicator = _getVariationIndicator(revenues[index], comparisons[index]);
                  }
                  return _buildStatLine(
                    periods[index],
                    '${_formatLargeNumber(revenues[index])} €',
                    percentageChange,
                    indicator,
                  );
                }),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatLine(String label, String value, double? percentageChange, String? indicator) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label : $value',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (indicator != null && percentageChange != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildIndicator(indicator),
                const SizedBox(width: 4),
                Text(
                  percentageChange >= 0
                      ? '+${percentageChange.toStringAsFixed(1)}%'
                      : '${percentageChange.toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: percentageChange >= 0
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.error,
                      ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  double _calculatePercentageChange(double current, double compare) {
    if (compare == 0) return 0.0;
    return ((current - compare) / compare) * 100;
  }

  String _formatLargeNumber(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M €';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K €';
    }
    return '${value.toStringAsFixed(2)} €';
  }

  String _getVariationIndicator(double current, double compare) {
    if (compare == 0) return '⚡';
    if (current > compare) return '↑';
    if (current < compare) return '↓';
    return '→';
  }

  Color _getIndicatorColor(String indicator) {
    switch (indicator) {
      case '↑':
        return Theme.of(context).colorScheme.primary;
      case '↓':
        return Theme.of(context).colorScheme.error;
      case '→':
      case '⚡':
        return Theme.of(context).colorScheme.onSurfaceVariant;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  Widget _buildIndicator(String indicator) {
    return Text(
      indicator,
      style: TextStyle(
        fontSize: 16,
        color: _getIndicatorColor(indicator),
        fontWeight: FontWeight.bold,
      ),
    );
  }
}