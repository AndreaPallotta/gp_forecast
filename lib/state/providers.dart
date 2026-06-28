import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database_service.dart';
import '../services/jolpica_api_service.dart';
import '../services/prediction_engine.dart';

class SyncState {
  final bool isSyncing;
  final String progressMessage;
  final String? errorMessage;

  SyncState({
    this.isSyncing = false,
    this.progressMessage = '',
    this.errorMessage,
  });

  SyncState copyWith({
    bool? isSyncing,
    String? progressMessage,
    String? errorMessage,
  }) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      progressMessage: progressMessage ?? this.progressMessage,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

// Global instances
final databaseServiceProvider = Provider((ref) => DatabaseService.instance);
final apiServiceProvider = Provider((ref) => JolpicaApiService());
final predictionEngineProvider = Provider((ref) => PredictionEngine());

// Selected Season & Round (defaulting to 2026, Round 1)
final selectedSeasonProvider = StateProvider<int>((ref) => 2026);
final selectedRoundProvider = StateProvider<int>((ref) => 1);

// Weather condition ('sunny', 'overcast', 'rainy')
final weatherProvider = StateProvider<String>((ref) => 'sunny');

// Synchronized Races List Provider
final racesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dbService = ref.watch(databaseServiceProvider);
  final season = ref.watch(selectedSeasonProvider);
  final db = await dbService.database;
  return await db.query(
    'races',
    where: 'season = ?',
    whereArgs: [season],
    orderBy: 'round ASC',
  );
});

// Sync State Notifier
class SyncNotifier extends StateNotifier<SyncState> {
  final JolpicaApiService _apiService;
  final Ref _ref;

  SyncNotifier(this._apiService, this._ref) : super(SyncState());

  Future<void> syncData() async {
    final season = _ref.read(selectedSeasonProvider);
    final round = _ref.read(selectedRoundProvider);
    
    state = SyncState(isSyncing: true, progressMessage: 'Connecting to Jolpica API...');
    
    try {
      // 1. Sync schedule
      state = state.copyWith(progressMessage: 'Downloading F1 $season schedule...');
      await _apiService.syncSchedule(season);
      
      // 2. Sync standings
      state = state.copyWith(progressMessage: 'Downloading driver standings...');
      await _apiService.syncStandings(season);
      
      // 3. Sync qualifying for current round
      state = state.copyWith(progressMessage: 'Downloading Qualifying results for Round $round...');
      await _apiService.syncQualifying(season, round);
      
      // 4. Sync race results for all completed races of the season
      state = state.copyWith(progressMessage: 'Downloading all season race results...');
      try {
        await _apiService.syncAllSeasonResults(season);
      } catch (e) {
        // Fallback to single round sync if season results fail or are empty
        try {
          await _apiService.syncResults(season, round);
        } catch (_) {}
      }

      state = SyncState(isSyncing: false, progressMessage: 'Data sync complete!');
      
      // Refresh races and prediction lists
      _ref.invalidate(racesProvider);
      _ref.invalidate(predictionsProvider);
    } catch (e) {
      state = SyncState(
        isSyncing: false,
        progressMessage: 'Sync failed',
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> clearCache() async {
    final dbService = _ref.read(databaseServiceProvider);
    state = SyncState(isSyncing: true, progressMessage: 'Clearing database...');
    await dbService.clearAllData();
    state = SyncState(isSyncing: false, progressMessage: 'Database cleared');
    _ref.invalidate(racesProvider);
    _ref.invalidate(predictionsProvider);
  }
}

final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return SyncNotifier(apiService, ref);
});

// Predictions Future Provider
final predictionsProvider = FutureProvider<List<DriverPrediction>>((ref) async {
  final dbService = ref.watch(databaseServiceProvider);
  final engine = ref.watch(predictionEngineProvider);
  final season = ref.watch(selectedSeasonProvider);
  final round = ref.watch(selectedRoundProvider);
  final weather = ref.watch(weatherProvider);

  final db = await dbService.database;

  // Find active circuitId for this race round
  final List<Map<String, dynamic>> race = await db.query(
    'races',
    columns: ['circuitId'],
    where: 'season = ? AND round = ?',
    whereArgs: [season, round],
  );

  final String circuitId = race.isNotEmpty ? race[0]['circuitId'] as String : 'unknown';

  return await engine.predictRace(
    season: season,
    round: round,
    circuitId: circuitId,
    weather: weather,
  );
});
