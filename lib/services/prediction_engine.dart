import 'database_service.dart';

class DriverPrediction {
  final String driverId;
  final String code;
  final String name;
  final String constructorName;
  final int gridPosition;
  final double baselineProbability;
  final double finalProbability;
  final int actualPosition;
  final String actualStatus;

  DriverPrediction({
    required this.driverId,
    required this.code,
    required this.name,
    required this.constructorName,
    required this.gridPosition,
    required this.baselineProbability,
    required this.finalProbability,
    this.actualPosition = 0,
    this.actualStatus = '',
  });
}

class PredictionEngine {
  final DatabaseService _dbService = DatabaseService.instance;

  // Track Overtaking Coefficients: higher values mean starting position matters MORE.
  static final Map<String, double> _overtakingCoefficients = {
    'monaco': 0.85,
    'singapore': 0.80,
    'hungaroring': 0.75,
    'albert_park': 0.65,
    'suzuka': 0.60,
    'bak': 0.55, // Baku
    'baku': 0.55,
    'marina_bay': 0.80,
    'silverstone': 0.50,
    'spa': 0.40,
    'monza': 0.35,
    'red_bull_ring': 0.45,
    'interlagos': 0.50,
    'americas': 0.50,
    'las_vegas': 0.45,
    'yas_marina': 0.55,
  };

  // Wet Weather driver skill multipliers: who performs best in wet/rain conditions.
  static final Map<String, double> _wetWeatherMultipliers = {
    'verstappen': 1.15,
    'hamilton': 1.12,
    'alonso': 1.10,
    'norris': 1.10,
    'leclerc': 1.05,
  };

  static double getOvertakingCoefficient(String circuitId) {
    return _overtakingCoefficients[circuitId] ?? 0.60; // Default coefficient
  }

  // Historical win percentages from specific grid slots.
  static double getGridWinProbability(int gridPosition) {
    switch (gridPosition) {
      case 1:
        return 0.45;
      case 2:
        return 0.20;
      case 3:
        return 0.12;
      case 4:
        return 0.08;
      case 5:
        return 0.05;
      case 6:
        return 0.03;
      case 7:
        return 0.02;
      case 8:
        return 0.015;
      case 9:
        return 0.01;
      case 10:
        return 0.008;
      default:
        // P11 to P20 share the remaining ~1.7%
        return 0.0017;
    }
  }

  // Primary prediction logic
  Future<List<DriverPrediction>> predictRace({
    required int season,
    required int round,
    required String circuitId,
    String weather = 'sunny',
  }) async {
    final db = await _dbService.database;

    // 1. Fetch standings to compute prior probability (strength of driver/car)
    final List<Map<String, dynamic>> standingsData = await db.query(
      'driver_standings',
      where: 'season = ? AND round = (SELECT MAX(round) FROM driver_standings WHERE season = ?)',
      whereArgs: [season, season],
    );

    // If no standings exist yet, we fall back to fetching all registered drivers
    final List<Map<String, dynamic>> driversData = await db.query('drivers');

    // Create a base strength map
    final Map<String, double> baselineStrengths = {};
    final Map<String, String> driverNames = {};
    final Map<String, String> driverCodes = {};
    final Map<String, String> driverConstructors = {};

    if (standingsData.isNotEmpty) {
      for (var row in standingsData) {
        final driverId = row['driverId'] as String;
        final points = (row['points'] as num).toDouble();
        final wins = (row['wins'] as num).toInt();
        final constructorName = row['constructorName'] as String;

        // Formula for driver baseline strength: points + (wins * 10) + constant prior offset
        baselineStrengths[driverId] = points + (wins * 10.0) + 5.0;
        driverConstructors[driverId] = constructorName;
      }
    } else {
      // Uniform prior fallback
      for (var row in driversData) {
        final driverId = row['driverId'] as String;
        baselineStrengths[driverId] = 1.0;
        driverConstructors[driverId] = 'Unknown Team';
      }
    }

    // Apply wet weather multipliers if active
    if (weather == 'rainy') {
      for (var driverId in baselineStrengths.keys) {
        final mult = _wetWeatherMultipliers[driverId] ?? 1.0;
        baselineStrengths[driverId] = baselineStrengths[driverId]! * mult;
      }
    }

    // Load names and codes for all drivers
    for (var row in driversData) {
      final driverId = row['driverId'] as String;
      final givenName = row['givenName'] as String;
      final familyName = row['familyName'] as String;
      final code = row['code'] as String;
      
      driverNames[driverId] = '$givenName $familyName';
      driverCodes[driverId] = code.isNotEmpty ? code : driverId.substring(0, 3).toUpperCase();
    }

    // Normalize baseline strengths into probabilities summing to 1.0
    final double totalStrength = baselineStrengths.values.fold(0, (sum, val) => sum + val);
    final Map<String, double> baselineProbabilities = {};
    baselineStrengths.forEach((driverId, strength) {
      baselineProbabilities[driverId] = totalStrength > 0 ? strength / totalStrength : 1.0 / baselineStrengths.length;
    });

    // 2. Fetch qualifying grid results
    final List<Map<String, dynamic>> qualyData = await db.query(
      'qualifying',
      where: 'raceId = ?',
      whereArgs: ['${season}_$round'],
    );

    final Map<String, int> gridPositions = {};
    for (var row in qualyData) {
      gridPositions[row['driverId'] as String] = row['position'] as int;
    }

    // Fetch actual race results
    final List<Map<String, dynamic>> resultsData = await db.query(
      'results',
      where: 'raceId = ?',
      whereArgs: ['${season}_$round'],
    );

    final Map<String, int> actualPositions = {};
    final Map<String, String> actualStatuses = {};
    for (var row in resultsData) {
      actualPositions[row['driverId'] as String] = row['position'] as int;
      actualStatuses[row['driverId'] as String] = row['status'] as String;
    }

    // 3. Compute final predictions
    final List<DriverPrediction> predictions = [];
    final double C = getOvertakingCoefficient(circuitId);

    // Collect all unique drivers in our system
    final allDrivers = baselineProbabilities.keys.toSet()
      ..addAll(gridPositions.keys);

    double totalFinalProb = 0.0;
    final Map<String, double> rawFinalProbabilities = {};

    for (var driverId in allDrivers) {
      final P_prior = baselineProbabilities[driverId] ?? 0.001;
      final gridPos = gridPositions[driverId] ?? 0;

      double finalProb;
      if (gridPos > 0) {
        // Grid position exists. Blend grid win rates with team/driver pace priors.
        final P_grid = getGridWinProbability(gridPos);
        
        // Linear blend: C * P_grid + (1-C) * P_prior
        finalProb = (C * P_grid) + ((1.0 - C) * P_prior);
      } else {
        // No qualifying yet. Rely purely on priors.
        finalProb = P_prior;
      }

      rawFinalProbabilities[driverId] = finalProb;
      totalFinalProb += finalProb;
    }

    // Normalize final probabilities to sum to exactly 100%
    for (var driverId in allDrivers) {
      final name = driverNames[driverId] ?? driverId;
      final code = driverCodes[driverId] ?? driverId.substring(0, 3).toUpperCase();
      final constructor = driverConstructors[driverId] ?? 'Unknown Team';
      final grid = gridPositions[driverId] ?? 0;
      final baseProb = baselineProbabilities[driverId] ?? 0.0;
      final rawProb = rawFinalProbabilities[driverId] ?? 0.0;
      
      final finalProb = totalFinalProb > 0 ? rawProb / totalFinalProb : 1.0 / allDrivers.length;

      final actualPos = actualPositions[driverId] ?? 0;
      final actualStat = actualStatuses[driverId] ?? '';

      predictions.add(DriverPrediction(
        driverId: driverId,
        code: code,
        name: name,
        constructorName: constructor,
        gridPosition: grid,
        baselineProbability: baseProb,
        finalProbability: finalProb,
        actualPosition: actualPos,
        actualStatus: actualStat,
      ));
    }

    // Sort descending by final probability
    predictions.sort((a, b) => b.finalProbability.compareTo(a.finalProbability));
    return predictions;
  }
}
