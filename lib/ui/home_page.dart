import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../state/providers.dart';
import 'live_simulator.dart';
import '../services/prediction_engine.dart';
import '../services/database_service.dart';
import 'theme.dart';
import 'responsive_layout.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _desktopLeftTab = 0; // 0 = Calendar, 1 = Drivers
  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncProvider);
    final selectedSeason = ref.watch(selectedSeasonProvider);
    final selectedRound = ref.watch(selectedRoundProvider);
    final racesAsync = ref.watch(racesProvider);
    final predictionsAsync = ref.watch(predictionsProvider);

    String circuitId = 'unknown';
    String circuitName = 'Unknown Circuit';
    bool isUpcoming = false;
    if (racesAsync.hasValue && racesAsync.value != null && racesAsync.value!.isNotEmpty) {
      final activeRace = racesAsync.value!.firstWhere(
        (r) => r['round'] == selectedRound,
        orElse: () => <String, dynamic>{},
      );
      circuitId = activeRace['circuitId'] ?? 'unknown';
      circuitName = activeRace['circuitName'] ?? 'Unknown Circuit';
      
      final String dateStr = activeRace['date'] ?? '';
      final String timeStr = activeRace['time'] ?? '';
      DateTime? raceDateTime;
      if (dateStr.isNotEmpty) {
        String combined = dateStr;
        if (timeStr.isNotEmpty) {
          combined = '$dateStr $timeStr';
        }
        raceDateTime = DateTime.tryParse(combined);
      }
      final now = DateTime.now();
      isUpcoming = raceDateTime == null || raceDateTime.isAfter(now);
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.f1Red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'GP',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'FORECAST',
              style: TextStyle(fontWeight: FontWeight.w300, fontSize: 18, letterSpacing: 2),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            onPressed: syncState.isSyncing
                ? null
                : () => ref.read(syncProvider.notifier).syncData(),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.textSecondary),
            onPressed: syncState.isSyncing
                ? null
                : () => ref.read(syncProvider.notifier).clearCache(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ResponsiveLayout(
            mobileBody: _buildMobileLayout(
              ref,
              syncState,
              selectedSeason,
              selectedRound,
              racesAsync,
              predictionsAsync,
              circuitId,
              circuitName,
              isUpcoming,
            ),
            desktopBody: _buildDesktopLayout(
              ref,
              syncState,
              selectedSeason,
              selectedRound,
              racesAsync,
              predictionsAsync,
              circuitId,
              circuitName,
              isUpcoming,
            ),
          ),
        ),
      ),
    );
  }

  // --- MOBILE LAYOUT ---
  Widget _buildMobileLayout(
    WidgetRef ref,
    SyncState syncState,
    int selectedSeason,
    int selectedRound,
    AsyncValue<List<Map<String, dynamic>>> racesAsync,
    AsyncValue<List<DriverPrediction>> predictionsAsync,
    String circuitId,
    String circuitName,
    bool isUpcoming,
  ) {
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSyncControlPanel(ref, syncState, selectedSeason, selectedRound),
          const SizedBox(height: 16),
          const TabBar(
            indicatorColor: AppColors.f1Red,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            dividerColor: Colors.transparent,
            tabs: [
              Tab(text: 'Predictions'),
              Tab(text: 'Calendar'),
              Tab(text: 'Drivers'),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              children: [
                _buildPredictionsList(predictionsAsync, circuitId, circuitName, selectedSeason, isUpcoming),
                _buildRacesList(ref, racesAsync, selectedRound, isMobile: true),
                _buildDriversList(selectedSeason),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- DESKTOP LAYOUT ---
  Widget _buildDesktopLayout(
    WidgetRef ref,
    SyncState syncState,
    int selectedSeason,
    int selectedRound,
    AsyncValue<List<Map<String, dynamic>>> racesAsync,
    AsyncValue<List<DriverPrediction>> predictionsAsync,
    String circuitId,
    String circuitName,
    bool isUpcoming,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Calendar & Controls
        SizedBox(
          width: 320,
          child: Column(
            children: [
              _buildSyncControlPanel(ref, syncState, selectedSeason, selectedRound),
              const SizedBox(height: 16),
              Expanded(
                child: GlassCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildDesktopLeftTabButton('CALENDAR', 0),
                          _buildDesktopLeftTabButton('DRIVERS', 1),
                        ],
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: _desktopLeftTab == 0
                            ? _buildRacesList(ref, racesAsync, selectedRound, isMobile: false)
                            : _buildDriversList(selectedSeason),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Right Column: Predictions list
        Expanded(
          child: _buildPredictionsList(predictionsAsync, circuitId, circuitName, selectedSeason, isUpcoming),
        ),
      ],
    );
  }

  // --- SYNC PANEL ---
  Widget _buildSyncControlPanel(WidgetRef ref, SyncState syncState, int selectedSeason, int selectedRound) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Season Dropdown
              const Text('Season: ', style: TextStyle(fontWeight: FontWeight.bold)),
              DropdownButton<int>(
                value: selectedSeason,
                items: [2023, 2024, 2025, 2026].map((int value) {
                  return DropdownMenuItem<int>(
                    value: value,
                    child: Text(value.toString()),
                  );
                }).toList(),
                onChanged: syncState.isSyncing
                    ? null
                    : (int? newValue) {
                        if (newValue != null) {
                          ref.read(selectedSeasonProvider.notifier).state = newValue;
                          // Reset round to 1 on season change
                          ref.read(selectedRoundProvider.notifier).state = 1;
                          ref.invalidate(racesProvider);
                          ref.invalidate(predictionsProvider);
                        }
                      },
                underline: const SizedBox(),
                dropdownColor: AppColors.cardBg,
              ),
              const Spacer(),
              // Sync Action Button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.f1Red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: syncState.isSyncing
                    ? null
                    : () => ref.read(syncProvider.notifier).syncData(),
                icon: syncState.isSyncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_outlined, size: 16),
                label: Text(syncState.isSyncing ? 'Syncing...' : 'Sync Season'),
              ),
            ],
          ),
          if (syncState.progressMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (syncState.isSyncing)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.accentNeonBlue),
                  )
                else
                  Icon(
                    syncState.errorMessage != null ? Icons.error_outline : Icons.check_circle_outline,
                    size: 14,
                    color: syncState.errorMessage != null ? Colors.redAccent : AppColors.accentNeonGreen,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    syncState.progressMessage,
                    style: TextStyle(
                      fontSize: 12,
                      color: syncState.isSyncing
                          ? AppColors.accentNeonBlue
                          : (syncState.errorMessage != null ? Colors.redAccent : AppColors.accentNeonGreen),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (syncState.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              syncState.errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  // --- RACES CALENDAR ---
  Widget _buildRacesList(
    WidgetRef ref,
    AsyncValue<List<Map<String, dynamic>>> racesAsync,
    int selectedRound, {
    required bool isMobile,
  }) {
    return racesAsync.when(
      data: (races) {
        if (races.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Text(
                'No schedule cached.\nClick "Sync Season" above.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          );
        }
        return ListView.builder(
          itemCount: races.length,
          itemBuilder: (context, index) {
            final race = races[index];
            final round = race['round'] as int;
            final isSelected = round == selectedRound;

            final String dateStr = race['date'] ?? '';
            final String timeStr = race['time'] ?? '';
            DateTime? raceDateTime;
            if (dateStr.isNotEmpty) {
              String combined = dateStr;
              if (timeStr.isNotEmpty) {
                combined = '$dateStr $timeStr';
              }
              raceDateTime = DateTime.tryParse(combined);
            }
            final now = DateTime.now();
            final bool isOver = raceDateTime != null && raceDateTime.isBefore(now);

            return Material(
              color: Colors.transparent,
              child: ListTile(
                selected: isSelected,
                selectedTileColor: AppColors.f1Red.withValues(alpha: 0.1),
                title: Text(
                  race['raceName'] ?? '',
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? AppColors.f1Red : AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Round $round • ${race['circuitName']}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    if (dateStr.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 10, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            dateStr,
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: isOver
                                    ? AppColors.glassBorder
                                    : AppColors.accentNeonBlue.withValues(alpha: 0.5),
                              ),
                              borderRadius: BorderRadius.circular(4),
                              color: isOver
                                  ? Colors.transparent
                                  : AppColors.accentNeonBlue.withValues(alpha: 0.1),
                            ),
                            child: Text(
                              isOver ? 'COMPLETED' : 'UPCOMING',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isOver
                                    ? AppColors.textSecondary
                                    : AppColors.accentNeonBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                trailing: isSelected
                    ? const Icon(Icons.chevron_right, color: AppColors.f1Red)
                    : const Icon(Icons.keyboard_arrow_right, color: AppColors.textSecondary),
                onTap: () {
                  ref.read(selectedRoundProvider.notifier).state = round;
                  ref.invalidate(predictionsProvider);
                },
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error loading calendar: $err')),
    );
  }

  // --- PREDICTIONS LIST ---
  Widget _buildPredictionsList(
    AsyncValue<List<DriverPrediction>> predictionsAsync,
    String circuitId,
    String circuitName,
    int season,
    bool isUpcoming,
  ) {
    return predictionsAsync.when(
      data: (predictions) {
        if (predictions.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Text(
                'No F1 data synchronized.\nSelect a race and click Sync.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          );
        }

        final activeWeather = ref.watch(weatherProvider);

        final weatherSelector = Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'WEATHER',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.5),
                ),
                Row(
                  children: [
                    _buildWeatherChip('SUNNY', 'sunny', Icons.wb_sunny_rounded, activeWeather),
                    const SizedBox(width: 6),
                    _buildWeatherChip('OVERCAST', 'overcast', Icons.cloud_rounded, activeWeather),
                    const SizedBox(width: 6),
                    _buildWeatherChip('RAINY', 'rainy', Icons.water_drop_rounded, activeWeather),
                  ],
                ),
              ],
            ),
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            weatherSelector,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'WIN PROBABILITIES',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                ),
                Row(
                  children: [
                    if (predictions.isNotEmpty && isUpcoming)
                      IconButton(
                        icon: const Icon(Icons.play_circle_fill_rounded, color: AppColors.f1Red),
                        tooltip: 'Launch Live Race Simulator',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LiveSimulationView(
                                season: season,
                                round: ref.read(selectedRoundProvider),
                                circuitId: circuitId,
                                circuitName: circuitName,
                                initialPredictions: predictions,
                              ),
                            ),
                          );
                        },
                      ),
                    Text(
                      '${predictions.length} classified',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: predictions.length,
                itemBuilder: (context, index) {
                  final pred = predictions[index];
                  final basePct = pred.baselineProbability * 100;
                  final finalPct = pred.finalProbability * 100;
                  final delta = finalPct - basePct;
                  final position = index + 1;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: Colors.transparent,
                    elevation: 0,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _showDriverDetails(
                        context,
                        pred,
                        circuitId,
                        circuitName,
                        season,
                        position,
                      ),
                      child: GlassCard(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                        children: [
                          Row(
                            children: [
                              // Position Badge
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: position <= 3 ? AppColors.f1Red : AppColors.glassBorder,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Center(
                                  child: Text(
                                    position.toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Driver Information
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          pred.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '(${pred.code})',
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      pred.constructorName,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    if (pred.actualPosition > 0) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            pred.actualPosition == position
                                                ? Icons.stars_rounded
                                                : Icons.compare_arrows_rounded,
                                            size: 11,
                                            color: pred.actualPosition == position
                                                ? AppColors.accentNeonGreen
                                                : AppColors.textSecondary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            pred.actualPosition == position
                                                ? 'Perfect Prediction'
                                                : (pred.actualPosition == 999
                                                    ? 'Pred: P$position | Finished: DNF'
                                                    : 'Pred: P$position | Finished: P${pred.actualPosition}'),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: pred.actualPosition == position
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color: pred.actualPosition == position
                                                  ? AppColors.accentNeonGreen
                                                  : AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              // Grid & Results Badges
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (pred.gridPosition > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: AppColors.glassBorder),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Grid: P${pred.gridPosition}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  if (pred.actualPosition > 0) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: pred.actualPosition == 999
                                            ? Colors.redAccent.withValues(alpha: 0.15)
                                            : (pred.actualPosition == 1
                                                ? AppColors.f1Red.withValues(alpha: 0.2)
                                                : AppColors.accentNeonGreen.withValues(alpha: 0.15)),
                                        border: Border.all(
                                          color: pred.actualPosition == 999
                                              ? Colors.redAccent
                                              : (pred.actualPosition == 1
                                                  ? AppColors.f1Red
                                                  : AppColors.accentNeonGreen),
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        pred.actualPosition == 999
                                            ? 'DNF'
                                            : 'Result: P${pred.actualPosition}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: pred.actualPosition == 999
                                              ? Colors.redAccent
                                              : (pred.actualPosition == 1
                                                  ? AppColors.f1Red
                                                  : AppColors.accentNeonGreen),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(width: 12),
                              // Final Percentage Display
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${finalPct.toStringAsFixed(1)}%',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                      color: AppColors.f1Red,
                                    ),
                                  ),
                                  // Delta Badge
                                  Row(
                                    children: [
                                      Icon(
                                        delta >= 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                                        color: delta >= 0 ? AppColors.accentNeonGreen : Colors.redAccent,
                                        size: 14,
                                      ),
                                      Text(
                                        '${delta.abs().toStringAsFixed(1)}%',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: delta >= 0 ? AppColors.accentNeonGreen : Colors.redAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Double Bar Chart Layout (F1 Red for final, gray for baseline)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Final Prob Bar
                              _buildBarChart(
                                percentage: pred.finalProbability,
                                color: AppColors.f1Red,
                                label: 'Race Probability',
                              ),
                              const SizedBox(height: 4),
                              // Baseline Prior Bar
                              _buildBarChart(
                                percentage: pred.baselineProbability,
                                color: AppColors.glassBorder,
                                label: 'Baseline Form',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            'Error loading predictions: $err',
            style: const TextStyle(color: Colors.redAccent),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  // Horizontal bar custom builder
  Widget _buildBarChart({
    required double percentage,
    required Color color,
    required String label,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: percentage.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: color == AppColors.f1Red
                      ? [
                          BoxShadow(
                            color: AppColors.f1Red.withValues(alpha: 0.3),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<Map<String, dynamic>?> _fetchDriverStandingsDetails(String driverId, int season) async {
    final db = await DatabaseService.instance.database;
    // Fetch standing info
    final List<Map<String, dynamic>> standings = await db.query(
      'driver_standings',
      where: 'season = ? AND driverId = ?',
      whereArgs: [season, driverId],
      orderBy: 'round DESC',
      limit: 1,
    );
    // Fetch metadata
    final List<Map<String, dynamic>> metadata = await db.query(
      'drivers',
      where: 'driverId = ?',
      whereArgs: [driverId],
      limit: 1,
    );

    if (standings.isEmpty && metadata.isEmpty) return null;

    final result = <String, dynamic>{};
    if (standings.isNotEmpty) {
      result.addAll(standings[0]);
    }
    if (metadata.isNotEmpty) {
      result.addAll(metadata[0]);
    }
    return result;
  }

  void _showDriverDetails(
    BuildContext context,
    DriverPrediction pred,
    String circuitId,
    String circuitName,
    int season,
    int predictedRank,
  ) {
    final coeff = PredictionEngine.getOvertakingCoefficient(circuitId);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            border: Border.all(
              color: AppColors.glassBorder.withValues(alpha: 0.5),
              width: 1.0,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // Top Drag Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.glassBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pred.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          pred.constructorName.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.f1Red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${(pred.finalProbability * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              // Prediction Analysis Section
              const Text(
                'PREDICTION ANALYSIS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: AppColors.f1Red,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                pred.gridPosition > 0
                    ? 'Starting from P${pred.gridPosition} at $circuitName. Since this track has an overtaking difficulty of ${(coeff * 100).toStringAsFixed(0)}% (where 100% means overtaking is nearly impossible), the starting grid represents ${(coeff * 100).toStringAsFixed(0)}% of the total prediction score, and team/driver season performance accounts for the remaining ${((1.0 - coeff) * 100).toStringAsFixed(0)}%.'
                    : 'Qualifying results are not yet available for this round. GPForecast is relying entirely on the driver\'s and team\'s season-long performance (prior points and wins).',
                style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              // Probability breakdown diagram
              _buildProbabilityDiagram(pred, coeff),
              if (pred.actualPosition > 0) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                const Text(
                  'RACE OUTCOME COMPARISON',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: AppColors.f1Red,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GlassCard(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            const Text(
                              'PREDICTED RANK',
                              style: TextStyle(fontSize: 9, color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'P$predictedRank',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GlassCard(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            const Text(
                              'ACTUAL FINISH',
                              style: TextStyle(fontSize: 9, color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              pred.actualPosition == 999 ? 'DNF' : 'P${pred.actualPosition}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: pred.actualPosition == 999
                                    ? Colors.redAccent
                                    : (pred.actualPosition == predictedRank
                                        ? AppColors.accentNeonGreen
                                        : AppColors.textPrimary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: pred.actualPosition == predictedRank
                        ? AppColors.accentNeonGreen.withValues(alpha: 0.1)
                        : AppColors.glassBorder.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: pred.actualPosition == predictedRank
                          ? AppColors.accentNeonGreen.withValues(alpha: 0.5)
                          : AppColors.glassBorder,
                    ),
                  ),
                  child: Text(
                    pred.actualPosition == predictedRank
                        ? '🎯 Model Accuracy Hit! The prediction model successfully predicted that ${pred.name} would finish in P$predictedRank.'
                        : (pred.actualPosition == 999
                            ? '❌ Driver Retired. ${pred.name} started from P${pred.gridPosition} but retired from the race (${pred.actualStatus}).'
                            : '📊 Model Delta: The driver finished ${pred.actualPosition > predictedRank ? '${pred.actualPosition - predictedRank} positions lower' : '${predictedRank - pred.actualPosition} positions higher'} than the predicted P$predictedRank.'),
                    style: TextStyle(
                      fontSize: 12,
                      color: pred.actualPosition == predictedRank ? AppColors.accentNeonGreen : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              // Async Driver Stats
              FutureBuilder<Map<String, dynamic>?>(
                future: _fetchDriverStandingsDetails(pred.driverId, season),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24.0),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final details = snapshot.data;
                  if (details == null) {
                    return const Center(child: Text('Standings details not available locally.'));
                  }

                  final points = details['points'] ?? 0.0;
                  final position = details['position'] ?? 0;
                  final wins = details['wins'] ?? 0;
                  final nationality = details['nationality'] ?? 'Unknown';
                  final code = details['code'] ?? pred.code;
                  final number = details['permanentNumber'] ?? 'N/A';

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SEASON STATISTICS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          color: AppColors.f1Red,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStatItem('STANDINGS POS', 'P$position'),
                          _buildStatItem('POINTS', '$points pts'),
                          _buildStatItem('WINS', '$wins'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStatItem('DRIVER CODE', code.toString()),
                          _buildStatItem('CAR NUMBER', '#$number'),
                          _buildStatItem('NATIONALITY', nationality.toString()),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      );
      },
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 9, color: AppColors.textSecondary, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProbabilityDiagram(DriverPrediction pred, double coeff) {
    final basePct = pred.baselineProbability * 100;
    final gridPct = PredictionEngine.getGridWinProbability(pred.gridPosition) * 100;
    final finalPct = pred.finalProbability * 100;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PROBABILITY DIAGRAM',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          _buildDiagramBar('Baseline Form', basePct, AppColors.textSecondary),
          if (pred.gridPosition > 0) ...[
            const SizedBox(height: 10),
            _buildDiagramBar('Grid Slot Win Rate', gridPct, AppColors.accentNeonBlue),
          ],
          const SizedBox(height: 10),
          _buildDiagramBar('Blended Win Chance', finalPct, AppColors.f1Red, isGlow: true),
        ],
      ),
    );
  }

  Widget _buildDiagramBar(String label, double value, Color color, {bool isGlow = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textPrimary)),
            Text('${value.toStringAsFixed(1)}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: (value / 100).clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                boxShadow: isGlow
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.4),
                          blurRadius: 6,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeatherChip(String label, String value, IconData icon, String activeWeather) {
    final isSelected = activeWeather == value;
    final activeColor = value == 'rainy'
        ? AppColors.accentNeonBlue
        : (value == 'overcast' ? AppColors.textSecondary : Colors.orangeAccent);

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        ref.read(weatherProvider.notifier).state = value;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.15) : Colors.transparent,
          border: Border.all(
            color: isSelected ? activeColor : AppColors.glassBorder,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 12,
              color: isSelected ? activeColor : AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: isSelected ? activeColor : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLeftTabButton(String label, int tabIndex) {
    final isSelected = _desktopLeftTab == tabIndex;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _desktopLeftTab = tabIndex;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? AppColors.f1Red : Colors.transparent,
                width: 2.0,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchSeasonDrivers(int season) async {
    final db = await DatabaseService.instance.database;
    final List<Map<String, dynamic>> joined = await db.rawQuery('''
      SELECT ds.*, d.givenName, d.familyName, d.code, d.nationality, d.permanentNumber
      FROM driver_standings ds
      LEFT JOIN drivers d ON ds.driverId = d.driverId
      WHERE ds.season = ? AND ds.round = (
        SELECT MAX(round) FROM driver_standings WHERE season = ?
      )
      ORDER BY ds.position ASC
    ''', [season, season]);
    
    return joined;
  }

  Future<List<Map<String, dynamic>>> _fetchDriverFinishes(String driverId, int season) async {
    final db = await DatabaseService.instance.database;
    final List<Map<String, dynamic>> data = await db.rawQuery('''
      SELECT r.round, r.raceName, res.position, res.status
      FROM results res
      JOIN races r ON res.raceId = r.raceId
      WHERE res.driverId = ? AND r.season = ?
      ORDER BY r.round ASC
    ''', [driverId, season]);
    return data;
  }

  Widget _buildDriverPerformanceChart(List<Map<String, dynamic>> finishes) {
    if (finishes.isEmpty) {
      return Container(
        height: 150,
        alignment: Alignment.center,
        child: const Text(
          'No historical race results synced yet.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
    }

    final spots = <FlSpot>[];
    for (var i = 0; i < finishes.length; i++) {
      final round = (finishes[i]['round'] as num).toDouble();
      final posNum = finishes[i]['position'] as num;
      // 999 or 0 means DNF/retired. Let's treat it as P21.
      final pos = posNum == 999 || posNum <= 0 ? 21.0 : posNum.toDouble();
      // Invert Y axis so P1 is at the top (range 1 to 21 -> inverts to 21 to 1)
      spots.add(FlSpot(round, 22.0 - pos));
    }

    return Container(
      height: 180,
      padding: const EdgeInsets.only(right: 16, top: 12, bottom: 8),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 5,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: AppColors.glassBorder.withValues(alpha: 0.15),
                strokeWidth: 1,
              );
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 5,
                getTitlesWidget: (value, meta) {
                  final pos = (22 - value).round();
                  if (pos == 21) return const Text('DNF', style: TextStyle(fontSize: 8, color: Colors.redAccent));
                  if (pos > 20 || pos < 1) return const SizedBox();
                  return Text('P$pos', style: const TextStyle(fontSize: 9, color: AppColors.textSecondary));
                },
                reservedSize: 28,
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 2,
                getTitlesWidget: (value, meta) {
                  return Text('R${value.round()}', style: const TextStyle(fontSize: 9, color: AppColors.textSecondary));
                },
                reservedSize: 20,
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 1,
          maxX: finishes.length.toDouble() > 5 ? finishes.length.toDouble() : 5,
          minY: 1,
          maxY: 21,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppColors.f1Red,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  final isDnf = spot.y == 1.0;
                  return FlDotCirclePainter(
                    radius: 4,
                    color: isDnf ? Colors.redAccent : AppColors.f1Red,
                    strokeWidth: 1.5,
                    strokeColor: Colors.white,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.f1Red.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDriverProfile(BuildContext context, Map<String, dynamic> driver, int season) {
    final driverId = driver['driverId'] as String;
    final givenName = driver['givenName'] ?? '';
    final familyName = driver['familyName'] ?? '';
    final fullName = '$givenName $familyName';
    final constructorName = driver['constructorName'] ?? 'Unknown Team';
    final code = driver['code'] ?? driverId.substring(0, 3).toUpperCase();
    final number = driver['permanentNumber'] ?? 'N/A';
    final nationality = driver['nationality'] ?? 'Unknown';
    final points = driver['points'] ?? 0.0;
    final wins = driver['wins'] ?? 0;
    final position = driver['position'] ?? 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            border: Border.all(
              color: AppColors.glassBorder.withValues(alpha: 0.5),
              width: 1.0,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.glassBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fullName,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            constructorName.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.glassBorder,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.f1Red),
                      ),
                      child: Text(
                        '#$number',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.f1Red,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 16),
                const Text(
                  'CHAMPIONSHIP STANDINGS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: AppColors.f1Red,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStatItem('STANDINGS POS', 'P$position'),
                    _buildStatItem('POINTS', '$points pts'),
                    _buildStatItem('WINS', '$wins'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStatItem('DRIVER CODE', code.toString()),
                    _buildStatItem('NATIONALITY', nationality.toString()),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                const Text(
                  'FINISHING POSITION HISTORY',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: AppColors.f1Red,
                  ),
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _fetchDriverFinishes(driverId, season),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 40.0),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    final finishes = snapshot.data ?? [];
                    return _buildDriverPerformanceChart(finishes);
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDriversList(int season) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchSeasonDrivers(season),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error loading drivers: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)));
        }
        final drivers = snapshot.data ?? [];
        if (drivers.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Text(
                'No F1 driver standings data.\nPlease Sync data first.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          itemCount: drivers.length,
          itemBuilder: (context, index) {
            final driver = drivers[index];
            final givenName = driver['givenName'] ?? '';
            final familyName = driver['familyName'] ?? '';
            final fullName = '$givenName $familyName';
            final constructorName = driver['constructorName'] ?? 'Unknown Team';
            final code = driver['code'] ?? driver['driverId']?.toString().substring(0, 3).toUpperCase() ?? '???';
            final points = driver['points'] ?? 0.0;
            final position = driver['position'] ?? (index + 1);

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: Colors.transparent,
              elevation: 0,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _showDriverProfile(context, driver, season),
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: position <= 3 ? AppColors.f1Red : AppColors.glassBorder,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            position.toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  fullName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '($code)',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              constructorName,
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '$points pts',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
