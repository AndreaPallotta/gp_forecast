import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  @visibleForTesting
  void setDatabaseForTesting(Database db) {
    _database = db;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('gp_forecast.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    String path;
    if (!kIsWeb && Platform.isWindows) {
      // Initialize FFI for Windows
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      
      final dbFolder = await getApplicationSupportDirectory();
      path = join(dbFolder.path, 'gp_forecast', filePath);
      
      // Ensure the directory exists
      final dir = Directory(dirname(path));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } else {
      // Standard mobile initialization
      path = join(await getDatabasesPath(), filePath);
    }

    return await openDatabase(
      path,
      version: 1,
      onCreate: createDB,
    );
  }

  Future<void> createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE drivers (
        driverId TEXT PRIMARY KEY,
        permanentNumber INTEGER,
        code TEXT,
        givenName TEXT,
        familyName TEXT,
        dateOfBirth TEXT,
        nationality TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE races (
        raceId TEXT PRIMARY KEY,
        season INTEGER,
        round INTEGER,
        circuitId TEXT,
        circuitName TEXT,
        raceName TEXT,
        date TEXT,
        time TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE qualifying (
        qualifyingId TEXT PRIMARY KEY,
        raceId TEXT,
        driverId TEXT,
        constructorId TEXT,
        constructorName TEXT,
        position INTEGER,
        q1 TEXT,
        q2 TEXT,
        q3 TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE results (
        resultId TEXT PRIMARY KEY,
        raceId TEXT,
        driverId TEXT,
        constructorId TEXT,
        constructorName TEXT,
        grid INTEGER,
        position INTEGER,
        points REAL,
        status TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE driver_standings (
        standingsId TEXT PRIMARY KEY,
        season INTEGER,
        round INTEGER,
        driverId TEXT,
        constructorId TEXT,
        constructorName TEXT,
        points REAL,
        position INTEGER,
        wins INTEGER
      )
    ''');
  }

  // Clear all data (useful for a fresh sync)
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('drivers');
    await db.delete('races');
    await db.delete('qualifying');
    await db.delete('results');
    await db.delete('driver_standings');
  }
}
