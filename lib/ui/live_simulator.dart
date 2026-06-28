import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/prediction_engine.dart';
import 'theme.dart';
import 'circuit_painter.dart';

class LiveSimulationView extends ConsumerStatefulWidget {
  final int season;
  final int round;
  final String circuitId;
  final String circuitName;
  final List<DriverPrediction> initialPredictions;

  const LiveSimulationView({
    super.key,
    required this.season,
    required this.round,
    required this.circuitId,
    required this.circuitName,
    required this.initialPredictions,
  });

  @override
  ConsumerState<LiveSimulationView> createState() => _LiveSimulationViewState();
}

class _LiveSimulationViewState extends ConsumerState<LiveSimulationView> {
  // Simulation config
  static const int totalLaps = 50;
  
  // Timer & State
  Timer? _timer;
  bool _isPlaying = false;
  int _currentLap = 0;
  int _speedMultiplier = 1; // 1x, 2x, 5x, 10x
  
  // Simulated telemetry data
  late List<SimulatedDriver> _drivers;
  final List<String> _dnfLog = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _resetSimulation();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _resetSimulation() {
    _timer?.cancel();
    _isPlaying = false;
    _currentLap = 0;
    _dnfLog.clear();

    // Initialize driver simulation state based on initial predictions
    _drivers = List.generate(widget.initialPredictions.length, (index) {
      final pred = widget.initialPredictions[index];
      // Grid position: default to index+1 if 0
      final grid = pred.gridPosition > 0 ? pred.gridPosition : index + 1;
      
      return SimulatedDriver(
        driverId: pred.driverId,
        code: pred.code,
        name: pred.name,
        constructorName: pred.constructorName,
        gridPosition: grid,
        currentPosition: grid, // Start at qualifying grid
        gapToLeader: 0.0,
        tyreAge: 0,
        tyreType: grid <= 10 ? 'Soft' : 'Medium',
        baselineStrength: pred.baselineProbability,
        liveProbability: pred.finalProbability,
        color: _getConstructorColor(pred.constructorName),
        trackProgress: 0.0,
      );
    });

    // Initial sort by position
    _drivers.sort((a, b) => a.currentPosition.compareTo(b.currentPosition));
    _recalculatePositionsAndGaps();
  }

  void _recalculatePositionsAndGaps() {
    double runningGap = 0.0;
    for (int i = 0; i < _drivers.length; i++) {
      final driver = _drivers[i];
      if (driver.isDnf) {
        driver.currentPosition = 999;
        driver.gapToLeader = 999.9;
        driver.liveProbability = 0.0;
        continue;
      }
      
      driver.currentPosition = i + 1;
      if (i == 0) {
        driver.gapToLeader = 0.0;
      } else {
        // Gap ranges between 0.3s to 2.5s per slot
        runningGap += 0.3 + _random.nextDouble() * 1.5;
        driver.gapToLeader = runningGap;
      }
    }

    // Dynamic win probability model recalculation based on current lap & track progress
    double totalProb = 0.0;
    final double lapProgressRatio = _currentLap / totalLaps; // 0.0 -> 1.0

    for (var driver in _drivers) {
      if (driver.isDnf) {
        driver.liveProbability = 0.0;
        continue;
      }

      // Standings/qualifying prior weight decays as the race approaches final laps
      final priorWeight = 1.0 - lapProgressRatio;
      
      // Track position weight increases as laps tick up
      final positionRatio = driver.currentPosition;
      double trackWeight = 0.0;
      if (positionRatio == 1) {
        trackWeight = 0.65;
      } else if (positionRatio == 2) {
        trackWeight = 0.20;
      } else if (positionRatio == 3) {
        trackWeight = 0.08;
      } else {
        trackWeight = 0.07 / positionRatio;
      }

      // Adjust track weight based on gap to leader
      trackWeight = trackWeight / (1.0 + driver.gapToLeader * 0.05);

      // Blend formula
      final blendedScore = (priorWeight * driver.baselineStrength) + (lapProgressRatio * trackWeight);
      driver.liveProbability = blendedScore;
      totalProb += blendedScore;
    }

    // Normalize live probabilities to sum to exactly 100%
    for (var driver in _drivers) {
      if (driver.isDnf) continue;
      driver.liveProbability = totalProb > 0 ? driver.liveProbability / totalProb : 1.0 / _drivers.length;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    final intervalMs = (1000 / _speedMultiplier).round();
    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      if (_currentLap >= totalLaps) {
        setState(() {
          _isPlaying = false;
          _timer?.cancel();
        });
        return;
      }

      setState(() {
        _currentLap++;
        _simulateLap();
      });
    });
  }

  void _simulateLap() {
    // 1. Simulating position changes, pit stops, and random mechanical failures
    for (int i = 0; i < _drivers.length; i++) {
      final driver = _drivers[i];
      if (driver.isDnf) continue;

      driver.tyreAge++;

      // Check for pit stops (tyres > 18 laps)
      if (driver.tyreAge > 18 && _random.nextDouble() < 0.15) {
        driver.tyreAge = 0;
        driver.tyreType = driver.tyreType == 'Soft' ? 'Medium' : 'Hard';
        // Drop back due to pit stop penalty (approx. 18-20s gap)
        driver.gapToLeader += 20.0;
      }

      // Small pace randomness
      final paceModifier = _random.nextDouble() * 0.5 - 0.25; // -0.25s to 0.25s
      
      // Standings/Grid factor - leaders perform slightly better
      final rankFactor = (20.0 - driver.currentPosition) * 0.02;

      // Adjust progression position
      driver.gapToLeader = max(0.0, driver.gapToLeader + paceModifier - rankFactor);

      // Random DNF check (0.3% chance per driver per lap)
      if (_random.nextDouble() < 0.003 && _currentLap > 2) {
        driver.isDnf = true;
        final dnfReasons = ['Engine Failure', 'Suspension Accident', 'Gearbox Issue', 'Spun Off', 'Puncture'];
        final reason = dnfReasons[_random.nextInt(dnfReasons.length)];
        driver.dnfReason = reason;
        _dnfLog.add('Lap $_currentLap: ${driver.name} retired ($reason)');
      }
    }

    // Sort active drivers by gap to leader
    final activeDrivers = _drivers.where((d) => !d.isDnf).toList();
    activeDrivers.sort((a, b) => a.gapToLeader.compareTo(b.gapToLeader));

    final dnfDrivers = _drivers.where((d) => d.isDnf).toList();

    // Reconstruct list
    _drivers = [...activeDrivers, ...dnfDrivers];

    // Compute progress around track metrics (points on painter)
    for (int i = 0; i < _drivers.length; i++) {
      final driver = _drivers[i];
      if (driver.isDnf) continue;
      
      // Animate circuit progression dots
      // Each lap, they advance progress. Let's offset them based on their position/gap
      final lapProgress = _currentLap / totalLaps;
      final gapOffset = driver.gapToLeader * 0.002;
      driver.trackProgress = (lapProgress + gapOffset + (i * 0.015)) % 1.0;
    }

    _recalculatePositionsAndGaps();
  }

  Color _getConstructorColor(String team) {
    final t = team.toLowerCase();
    if (t.contains('red bull')) return const Color(0xFF0600EF);
    if (t.contains('mclaren')) return const Color(0xFFFF8700);
    if (t.contains('ferrari')) return const Color(0xFFDC0000);
    if (t.contains('mercedes')) return const Color(0xFF00D2BE);
    if (t.contains('aston martin')) return const Color(0xFF006F62);
    if (t.contains('alpine')) return const Color(0xFFFF87BC);
    if (t.contains('williams')) return const Color(0xFF005AFF);
    if (t.contains('haas')) return const Color(0xFF787878);
    if (t.contains('sauber') || t.contains('kick')) return const Color(0xFF52FF00);
    if (t.contains('rb') || t.contains('visa')) return const Color(0xFF4E77FF);
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    // Generate data list for vector dots painter
    final List<Map<String, dynamic>> progressData = _drivers.where((d) => !d.isDnf).map((d) {
      return {
        'code': d.code,
        'progress': d.trackProgress,
        'color': d.color,
        'isLeader': d.currentPosition == 1,
      };
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'LIVE RACE SIMULATOR',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: AppColors.f1Red,
              ),
            ),
            Text(
              widget.circuitName.toUpperCase(),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.textSecondary),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 850;
              
              final trackPanel = GlassCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    // Lap details header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'RACE PROGRESS',
                              style: TextStyle(fontSize: 9, color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Lap $_currentLap / $totalLaps',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                          ],
                        ),
                        // Speed selector
                        Row(
                          children: [
                            _buildSpeedButton(1),
                            _buildSpeedButton(2),
                            _buildSpeedButton(5),
                            _buildSpeedButton(10),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Vector circuit painting canvas
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Stack(
                          children: [
                            CustomPaint(
                              painter: CircuitPainter(
                                circuitId: widget.circuitId,
                                trackColor: AppColors.accentNeonBlue,
                              ),
                              size: Size.infinite,
                            ),
                            CustomPaint(
                              painter: LiveDriverDotsPainter(
                                circuitId: widget.circuitId,
                                driverProgress: progressData,
                              ),
                              size: Size.infinite,
                            ),
                            if (_dnfLog.isNotEmpty)
                              Positioned(
                                bottom: 8,
                                left: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.8),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.warning_rounded, color: Colors.redAccent, size: 10),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _dnfLog.last,
                                          style: const TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Main controls row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.replay_rounded, size: 28, color: AppColors.textSecondary),
                          onPressed: _resetSimulation,
                        ),
                        const SizedBox(width: 20),
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: AppColors.f1Red,
                          child: IconButton(
                            icon: Icon(
                              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              size: 32,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPlaying = !_isPlaying;
                                if (_isPlaying) {
                                  _startTimer();
                                } else {
                                  _timer?.cancel();
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );

              final listPanel = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'LIVE STANDINGS',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.5),
                        ),
                        Text(
                          'WIN PROBABILITY',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _drivers.length,
                      itemBuilder: (context, index) {
                        final d = _drivers[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: Colors.transparent,
                          elevation: 0,
                          child: GlassCard(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                // Position indicator
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: d.isDnf 
                                        ? Colors.redAccent.withValues(alpha: 0.1) 
                                        : (d.currentPosition <= 3 ? AppColors.f1Red : AppColors.glassBorder),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Center(
                                    child: Text(
                                      d.isDnf ? 'OUT' : d.currentPosition.toString(),
                                      style: TextStyle(
                                        fontSize: 9, 
                                        fontWeight: FontWeight.bold, 
                                        color: d.isDnf ? Colors.redAccent : Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Colored indicator bar
                                Container(
                                  width: 3.5,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: d.color,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Name & Tyre details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            d.name,
                                            style: TextStyle(
                                              fontSize: 13, 
                                              fontWeight: FontWeight.bold,
                                              color: d.isDnf ? AppColors.textSecondary : AppColors.textPrimary,
                                              decoration: d.isDnf ? TextDecoration.lineThrough : null,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '(${d.code})',
                                            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        d.isDnf 
                                            ? 'Retired: ${d.dnfReason}' 
                                            : 'Gap: ${d.currentPosition == 1 ? "Leader" : "+${d.gapToLeader.toStringAsFixed(1)}s"} | ${d.tyreType} (${d.tyreAge} laps)',
                                        style: TextStyle(
                                          fontSize: 9, 
                                          color: d.isDnf ? Colors.redAccent : AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Win chance percent
                                Text(
                                  d.isDnf ? '0.0%' : '${(d.liveProbability * 100).toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: d.isDnf ? AppColors.textSecondary : AppColors.f1Red,
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
              );

              if (isWide) {
                return Row(
                  children: [
                    Expanded(flex: 3, child: trackPanel),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: listPanel),
                  ],
                );
              } else {
                return Column(
                  children: [
                    Expanded(flex: 4, child: trackPanel),
                    const SizedBox(height: 16),
                    Expanded(flex: 3, child: listPanel),
                  ],
                );
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedButton(int factor) {
    final isSelected = _speedMultiplier == factor;
    return InkWell(
      onTap: () {
        setState(() {
          _speedMultiplier = factor;
          if (_isPlaying) {
            _startTimer();
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.f1Red : AppColors.glassBorder.withValues(alpha: 0.1),
          border: Border.all(color: isSelected ? AppColors.f1Red : AppColors.glassBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${factor}x',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class SimulatedDriver {
  final String driverId;
  final String code;
  final String name;
  final String constructorName;
  final int gridPosition;
  int currentPosition;
  double gapToLeader;
  int tyreAge;
  String tyreType;
  final double baselineStrength;
  double liveProbability;
  final Color color;
  double trackProgress;
  bool isDnf;
  String dnfReason;

  SimulatedDriver({
    required this.driverId,
    required this.code,
    required this.name,
    required this.constructorName,
    required this.gridPosition,
    required this.currentPosition,
    required this.gapToLeader,
    required this.tyreAge,
    required this.tyreType,
    required this.baselineStrength,
    required this.liveProbability,
    required this.color,
    required this.trackProgress,
    this.isDnf = false,
    this.dnfReason = '',
  });
}
