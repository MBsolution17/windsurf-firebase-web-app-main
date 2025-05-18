import 'package:flutter/material.dart';

/// Extension sur la classe Color pour ajouter les méthodes et getters manquants
/// nécessaires pour les packages Syncfusion.
extension ColorExtension on Color {
  /// Méthode manquante 'withValues' utilisée par Syncfusion
  /// Cette méthode est similaire à withOpacity mais avec un paramètre nommé.
  Color withValues({double? alpha}) {
    return withOpacity(alpha ?? opacity);
  }
  
  /// Getters pour les composantes R, G, B, A comme décimales (0.0-1.0)
  /// Ces getters sont utilisés par Syncfusion mais ne sont pas définis dans Flutter
  double get r => red / 255.0;
  double get g => green / 255.0;
  double get b => blue / 255.0;
  double get a => opacity;
}