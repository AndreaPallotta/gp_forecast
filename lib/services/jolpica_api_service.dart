import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'database_service.dart';

class JolpicaApiService {
  static const String baseUrl = 'https://api.jolpi.ca/ergast/f1';
  final DatabaseService _dbService = DatabaseService.instance;

  // Sync Season Schedule
  Future<void> syncSchedule(int season) async {
    final response = await http.get(Uri.parse('$baseUrl/$season.json?limit=100'));
    if (response.statusCode != 200) {
      throw Exception('Failed to load schedule from Jolpica API');
    }

    final data = json.decode(response.body);
    final races = data['MRData']['RaceTable']['Races'] as List<dynamic>? ?? [];

    final db = await _dbService.database;
    await db.transaction((txn) async {
      for (var race in races) {
        final circuit = race['Circuit'];
        await txn.insert(
          'races',
          {
            'raceId': '${race['season']}_${race['round']}',
            'season': int.parse(race['season']),
            'round': int.parse(race['round']),
            'circuitId': circuit['circuitId'],
            'circuitName': circuit['circuitName'],
            'raceName': race['raceName'],
            'date': race['date'] ?? '',
            'time': race['time'] ?? '',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  // Sync Standings
  Future<void> syncStandings(int season) async {
    final response = await http.get(Uri.parse('$baseUrl/$season/driverStandings.json?limit=100'));
    if (response.statusCode != 200) {
      throw Exception('Failed to load standings from Jolpica API');
    }

    final data = json.decode(response.body);
    final standingsLists = data['MRData']['StandingsTable']['StandingsLists'] as List<dynamic>? ?? [];
    if (standingsLists.isEmpty) return;

    final round = int.parse(standingsLists[0]['round']);
    final standings = standingsLists[0]['DriverStandings'] as List<dynamic>? ?? [];

    final db = await _dbService.database;
    await db.transaction((txn) async {
      for (var row in standings) {
        final driver = row['Driver'];
        final constructor = (row['Constructors'] as List<dynamic>).isNotEmpty
            ? row['Constructors'][0]
            : {'constructorId': 'unknown', 'name': 'Unknown'};

        // 1. Sync Driver metadata
        await txn.insert(
          'drivers',
          {
            'driverId': driver['driverId'],
            'permanentNumber': int.tryParse(driver['permanentNumber'] ?? ''),
            'code': driver['code'] ?? '',
            'givenName': driver['givenName'] ?? '',
            'familyName': driver['familyName'] ?? '',
            'dateOfBirth': driver['dateOfBirth'] ?? '',
            'nationality': driver['nationality'] ?? '',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // 2. Sync Standings row
        await txn.insert(
          'driver_standings',
          {
            'standingsId': '${season}_${round}_${driver['driverId']}',
            'season': season,
            'round': round,
            'driverId': driver['driverId'],
            'constructorId': constructor['constructorId'],
            'constructorName': constructor['name'],
            'points': double.tryParse(row['points'].toString()) ?? 0.0,
            'position': int.parse(row['position'].toString()),
            'wins': int.parse(row['wins'].toString()),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  // Sync Qualifying Results
  Future<void> syncQualifying(int season, int round) async {
    final response = await http.get(Uri.parse('$baseUrl/$season/$round/qualifying.json'));
    if (response.statusCode != 200) {
      throw Exception('Failed to load qualifying results');
    }

    final data = json.decode(response.body);
    final races = data['MRData']['RaceTable']['Races'] as List<dynamic>? ?? [];
    if (races.isEmpty) return;

    final qualyResults = races[0]['QualifyingResults'] as List<dynamic>? ?? [];
    final db = await _dbService.database;

    await db.transaction((txn) async {
      for (var result in qualyResults) {
        final driver = result['Driver'];
        final constructor = result['Constructor'];

        // Sync Driver metadata
        await txn.insert(
          'drivers',
          {
            'driverId': driver['driverId'],
            'permanentNumber': int.tryParse(driver['permanentNumber'] ?? ''),
            'code': driver['code'] ?? '',
            'givenName': driver['givenName'] ?? '',
            'familyName': driver['familyName'] ?? '',
            'dateOfBirth': driver['dateOfBirth'] ?? '',
            'nationality': driver['nationality'] ?? '',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // Sync Qualifying row
        await txn.insert(
          'qualifying',
          {
            'qualifyingId': '${season}_${round}_${driver['driverId']}',
            'raceId': '${season}_$round',
            'driverId': driver['driverId'],
            'constructorId': constructor['constructorId'],
            'constructorName': constructor['name'],
            'position': int.parse(result['position'].toString()),
            'q1': result['Q1'] ?? '',
            'q2': result['Q2'] ?? '',
            'q3': result['Q3'] ?? '',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  // Sync Race Results
  Future<void> syncResults(int season, int round) async {
    final response = await http.get(Uri.parse('$baseUrl/$season/$round/results.json'));
    if (response.statusCode != 200) {
      throw Exception('Failed to load race results');
    }

    final data = json.decode(response.body);
    final races = data['MRData']['RaceTable']['Races'] as List<dynamic>? ?? [];
    if (races.isEmpty) return;

    final results = races[0]['Results'] as List<dynamic>? ?? [];
    final db = await _dbService.database;

    await db.transaction((txn) async {
      for (var result in results) {
        final driver = result['Driver'];
        final constructor = result['Constructor'];

        // Sync Driver metadata
        await txn.insert(
          'drivers',
          {
            'driverId': driver['driverId'],
            'permanentNumber': int.tryParse(driver['permanentNumber'] ?? ''),
            'code': driver['code'] ?? '',
            'givenName': driver['givenName'] ?? '',
            'familyName': driver['familyName'] ?? '',
            'dateOfBirth': driver['dateOfBirth'] ?? '',
            'nationality': driver['nationality'] ?? '',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // Sync Result row
        await txn.insert(
          'results',
          {
            'resultId': '${season}_${round}_${driver['driverId']}',
            'raceId': '${season}_$round',
            'driverId': driver['driverId'],
            'constructorId': constructor['constructorId'],
            'constructorName': constructor['name'],
            'grid': int.parse(result['grid'].toString()),
            'position': int.tryParse(result['position']?.toString() ?? '') ?? 999, // 999 = DNF/Retired/Not classified
            'points': double.tryParse(result['points'].toString()) ?? 0.0,
            'status': result['status'] ?? '',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  // Sync All Race Results for the season (with pagination support)
  Future<void> syncAllSeasonResults(int season) async {
    final db = await _dbService.database;
    int offset = 0;
    const int limit = 100;
    bool hasMore = true;

    while (hasMore) {
      final response = await http.get(
        Uri.parse('$baseUrl/$season/results.json?limit=$limit&offset=$offset'),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to load season race results at offset $offset');
      }

      final data = json.decode(response.body);
      final races = data['MRData']['RaceTable']['Races'] as List<dynamic>? ?? [];
      if (races.isEmpty) {
        hasMore = false;
        break;
      }

      await db.transaction((txn) async {
        for (var race in races) {
          final roundStr = race['round'].toString();
          final round = int.parse(roundStr);
          final raceId = '${season}_$round';
          final results = race['Results'] as List<dynamic>? ?? [];

          for (var result in results) {
            final driver = result['Driver'];
            final constructor = result['Constructor'];

            // Sync Driver metadata
            await txn.insert(
              'drivers',
              {
                'driverId': driver['driverId'],
                'permanentNumber': int.tryParse(driver['permanentNumber']?.toString() ?? ''),
                'code': driver['code'] ?? '',
                'givenName': driver['givenName'] ?? '',
                'familyName': driver['familyName'] ?? '',
                'dateOfBirth': driver['dateOfBirth'] ?? '',
                'nationality': driver['nationality'] ?? '',
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );

            // Sync Result row
            await txn.insert(
              'results',
              {
                'resultId': '${season}_${round}_${driver['driverId']}',
                'raceId': raceId,
                'driverId': driver['driverId'],
                'constructorId': constructor['constructorId'],
                'constructorName': constructor['name'],
                'grid': int.tryParse(result['grid']?.toString() ?? '') ?? 0,
                'position': int.tryParse(result['position']?.toString() ?? '') ?? 999, // 999 = DNF
                'points': double.tryParse(result['points']?.toString() ?? '') ?? 0.0,
                'status': result['status'] ?? '',
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      });

      final total = int.tryParse(data['MRData']['total']?.toString() ?? '') ?? 0;
      offset += limit;
      if (offset >= total) {
        hasMore = false;
      }
    }
  }
}
