import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gp_forecast/services/database_service.dart';
import 'package:gp_forecast/services/prediction_engine.dart';
import 'package:gp_forecast/services/jolpica_api_service.dart';

void main() {
  // Initialize sqflite FFI for test environment
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late PredictionEngine engine;

  setUp(() async {
    // Open in-memory database
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) => DatabaseService.instance.createDB(db, version),
    );

    // Inject mocked database into the singleton
    DatabaseService.instance.setDatabaseForTesting(db);
    engine = PredictionEngine();
  });

  tearDown(() async {
    await db.close();
  });

  test('Prediction sums to 100% and matches standings without qualifying results', () async {
    // 1. Insert mock drivers
    await db.insert('drivers', {'driverId': 'verstappen', 'code': 'VER', 'givenName': 'Max', 'familyName': 'Verstappen'});
    await db.insert('drivers', {'driverId': 'norris', 'code': 'NOR', 'givenName': 'Lando', 'familyName': 'Norris'});
    await db.insert('drivers', {'driverId': 'leclerc', 'code': 'LEC', 'givenName': 'Charles', 'familyName': 'Leclerc'});

    // 2. Insert standings: Verstappen has 100 pts + 2 wins; Norris has 80 pts + 1 win; Leclerc has 50 pts + 0 wins
    await db.insert('driver_standings', {'standingsId': '1', 'season': 2024, 'round': 1, 'driverId': 'verstappen', 'constructorId': 'red_bull', 'constructorName': 'Red Bull', 'points': 100.0, 'position': 1, 'wins': 2});
    await db.insert('driver_standings', {'standingsId': '2', 'season': 2024, 'round': 1, 'driverId': 'norris', 'constructorId': 'mclaren', 'constructorName': 'McLaren', 'points': 80.0, 'position': 2, 'wins': 1});
    await db.insert('driver_standings', {'standingsId': '3', 'season': 2024, 'round': 1, 'driverId': 'leclerc', 'constructorId': 'ferrari', 'constructorName': 'Ferrari', 'points': 50.0, 'position': 3, 'wins': 0});

    // Run prediction (no qualifying in DB yet)
    final predictions = await engine.predictRace(season: 2024, round: 2, circuitId: 'monza');

    expect(predictions, hasLength(3));

    // Verify ordering is based on standings strength: Verstappen (100+20+5=125) > Norris (80+10+5=95) > Leclerc (50+0+5=55)
    expect(predictions[0].driverId, equals('verstappen'));
    expect(predictions[1].driverId, equals('norris'));
    expect(predictions[2].driverId, equals('leclerc'));

    // Check sum of probabilities equals 1.0 (100%)
    double totalProbability = predictions.fold(0.0, (sum, p) => sum + p.finalProbability);
    expect(totalProbability, closeTo(1.0, 0.0001));
  });

  test('Qualifying results adjust win probability', () async {
    // Setup drivers and standings
    await db.insert('drivers', {'driverId': 'verstappen', 'code': 'VER', 'givenName': 'Max', 'familyName': 'Verstappen'});
    await db.insert('drivers', {'driverId': 'norris', 'code': 'NOR', 'givenName': 'Lando', 'familyName': 'Norris'});
    
    // Verstappen has more points (100 vs 50)
    await db.insert('driver_standings', {'standingsId': '1', 'season': 2024, 'round': 1, 'driverId': 'verstappen', 'constructorId': 'red_bull', 'constructorName': 'Red Bull', 'points': 100.0, 'position': 1, 'wins': 1});
    await db.insert('driver_standings', {'standingsId': '2', 'season': 2024, 'round': 1, 'driverId': 'norris', 'constructorId': 'mclaren', 'constructorName': 'McLaren', 'points': 50.0, 'position': 2, 'wins': 0});

    // 2. Norris qualifies P1 (Pole), Verstappen qualifies P2
    await db.insert('qualifying', {'qualifyingId': 'q1', 'raceId': '2024_2', 'driverId': 'norris', 'constructorId': 'mclaren', 'constructorName': 'McLaren', 'position': 1});
    await db.insert('qualifying', {'qualifyingId': 'q2', 'raceId': '2024_2', 'driverId': 'verstappen', 'constructorId': 'red_bull', 'constructorName': 'Red Bull', 'position': 2});

    // Calculate at Monaco (high overtaking coefficient, P1 should be highly favored)
    final predictionsMonaco = await engine.predictRace(season: 2024, round: 2, circuitId: 'monaco');
    
    // Norris should jump to P1 in prediction because Monaco coefficient is 0.80+ (grid is dominant)
    expect(predictionsMonaco[0].driverId, equals('norris'));
    
    // Calculate at Monza (low overtaking coefficient, Verstappen's standings form should carry more weight)
    final predictionsMonza = await engine.predictRace(season: 2024, round: 2, circuitId: 'monza');

    // At Monza, grid position matters less. Let's verify Norris's probability is lower at Monza than Monaco.
    final norrisProbMonaco = predictionsMonaco.firstWhere((p) => p.driverId == 'norris').finalProbability;
    final norrisProbMonza = predictionsMonza.firstWhere((p) => p.driverId == 'norris').finalProbability;
    
    expect(norrisProbMonaco, greaterThan(norrisProbMonza));
  });

  test('Rainy weather adjusts win probability for specialists', () async {
    // 1. Setup mock data
    await db.insert('drivers', {'driverId': 'verstappen', 'code': 'VER', 'givenName': 'Max', 'familyName': 'Verstappen'});
    await db.insert('drivers', {'driverId': 'leclerc', 'code': 'LEC', 'givenName': 'Charles', 'familyName': 'Leclerc'});

    // Initialize with identical standings
    await db.insert('driver_standings', {'standingsId': '1', 'season': 2024, 'round': 1, 'driverId': 'verstappen', 'constructorId': 'red_bull', 'constructorName': 'Red Bull', 'points': 50.0, 'position': 1, 'wins': 0});
    await db.insert('driver_standings', {'standingsId': '2', 'season': 2024, 'round': 1, 'driverId': 'leclerc', 'constructorId': 'ferrari', 'constructorName': 'Ferrari', 'points': 50.0, 'position': 2, 'wins': 0});

    // Predictions on sunny day: they should be exactly identical
    final predictionsSunny = await engine.predictRace(season: 2024, round: 2, circuitId: 'monza', weather: 'sunny');
    final verSunny = predictionsSunny.firstWhere((p) => p.driverId == 'verstappen').finalProbability;
    final lecSunny = predictionsSunny.firstWhere((p) => p.driverId == 'leclerc').finalProbability;
    expect(verSunny, closeTo(lecSunny, 0.001));

    // Predictions on rainy day: Verstappen (1.15) should be favored over Leclerc (1.05)
    final predictionsRainy = await engine.predictRace(season: 2024, round: 2, circuitId: 'monza', weather: 'rainy');
    final verRainy = predictionsRainy.firstWhere((p) => p.driverId == 'verstappen').finalProbability;
    final lecRainy = predictionsRainy.firstWhere((p) => p.driverId == 'leclerc').finalProbability;
    expect(verRainy, greaterThan(lecRainy));
  });
}
