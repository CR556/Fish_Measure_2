import * as SQLite from 'expo-sqlite';

import type { CatchFilter, CatchRecord, CatchSort } from './types';

const DATABASE_NAME = 'fish-measure-2.db';
const SCHEMA_VERSION = 1;

let databasePromise: Promise<SQLite.SQLiteDatabase> | null = null;

export function getDatabase() {
  databasePromise ??= openDatabase();
  return databasePromise;
}

async function openDatabase() {
  const db = await SQLite.openDatabaseAsync(DATABASE_NAME);
  await db.execAsync('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;');
  await migrate(db);
  return db;
}

async function migrate(db: SQLite.SQLiteDatabase) {
  const result = await db.getFirstAsync<{ user_version: number }>('PRAGMA user_version');
  const current = result?.user_version ?? 0;
  if (current > SCHEMA_VERSION) {
    throw new Error(`Database schema ${current} is newer than this app supports.`);
  }
  if (current < 1) {
    await db.withExclusiveTransactionAsync(async (txn) => {
      await txn.execAsync(`
        CREATE TABLE catches (
          id TEXT PRIMARY KEY NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          measure_mode TEXT NOT NULL CHECK (measure_mode IN ('auto','manual')),
          length_curved_m REAL NOT NULL,
          length_chord_m REAL NOT NULL,
          length_source TEXT NOT NULL,
          girth_m REAL,
          girth_source TEXT NOT NULL,
          weight_kg REAL,
          weight_source TEXT NOT NULL,
          weight_formula TEXT,
          measure_confidence REAL NOT NULL,
          distance_m REAL NOT NULL,
          depth_coverage REAL NOT NULL,
          species_id TEXT,
          species_confidence REAL,
          species_source TEXT NOT NULL CHECK (species_source IN ('ai','user','none')),
          ai_suggestions TEXT,
          user_corrected INTEGER NOT NULL DEFAULT 0,
          bait TEXT,
          bait_source TEXT NOT NULL CHECK (bait_source IN ('ai','user','none')),
          lat REAL,
          lon REAL,
          loc_accuracy_m REAL,
          location_timestamp INTEGER,
          location_label TEXT,
          photo_path TEXT NOT NULL,
          thumb_path TEXT NOT NULL,
          ply_path TEXT,
          mask_path TEXT,
          contour_json_path TEXT NOT NULL,
          notes TEXT NOT NULL DEFAULT '',
          units_at_capture TEXT NOT NULL CHECK (units_at_capture IN ('imperial','metric')),
          photo_source TEXT NOT NULL,
          photo_width INTEGER NOT NULL,
          photo_height INTEGER NOT NULL,
          registration_status TEXT NOT NULL,
          registration_score REAL,
          capture_frame_id INTEGER NOT NULL,
          algorithm_version TEXT NOT NULL,
          schema_version INTEGER NOT NULL
        );
        CREATE INDEX catches_created_at_idx ON catches(created_at DESC);
        CREATE INDEX catches_species_idx ON catches(species_id);
        CREATE INDEX catches_length_idx ON catches(length_curved_m);
        CREATE INDEX catches_weight_idx ON catches(weight_kg);

        CREATE TABLE id_queue (
          catch_id TEXT PRIMARY KEY NOT NULL,
          enqueued_at INTEGER NOT NULL,
          attempts INTEGER NOT NULL DEFAULT 0,
          last_attempt_at INTEGER,
          next_attempt_at INTEGER NOT NULL,
          last_error TEXT,
          request_id TEXT,
          status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','running','manual')),
          FOREIGN KEY(catch_id) REFERENCES catches(id) ON DELETE CASCADE
        );
      `);
      await txn.execAsync('PRAGMA user_version = 1');
    });
  }
}

const catchColumns: (keyof CatchRecord)[] = [
  'id', 'created_at', 'updated_at', 'measure_mode', 'length_curved_m',
  'length_chord_m', 'length_source', 'girth_m', 'girth_source', 'weight_kg',
  'weight_source', 'weight_formula', 'measure_confidence', 'distance_m',
  'depth_coverage', 'species_id', 'species_confidence', 'species_source',
  'ai_suggestions', 'user_corrected', 'bait', 'bait_source', 'lat', 'lon',
  'loc_accuracy_m', 'location_timestamp', 'location_label', 'photo_path',
  'thumb_path', 'ply_path', 'mask_path', 'contour_json_path', 'notes',
  'units_at_capture', 'photo_source', 'photo_width', 'photo_height',
  'registration_status', 'registration_score', 'capture_frame_id',
  'algorithm_version', 'schema_version',
];

export async function insertCatch(record: CatchRecord) {
  const db = await getDatabase();
  const placeholders = catchColumns.map(() => '?').join(',');
  const values = catchColumns.map((column) => record[column] as SQLite.SQLiteBindValue);
  await db.runAsync(
    `INSERT INTO catches (${catchColumns.join(',')}) VALUES (${placeholders})`,
    values
  );
}

export async function getCatch(id: string) {
  const db = await getDatabase();
  return db.getFirstAsync<CatchRecord>('SELECT * FROM catches WHERE id = ?', id);
}

export async function deleteCatchRow(id: string) {
  const db = await getDatabase();
  await db.runAsync('DELETE FROM catches WHERE id = ?', id);
}

export async function listCatches(
  filter: CatchFilter = {},
  sort: CatchSort = 'newest',
  limit = 100,
  offset = 0
) {
  const where: string[] = [];
  const values: SQLite.SQLiteBindValue[] = [];
  const add = (clause: string, value: SQLite.SQLiteBindValue) => {
    where.push(clause);
    values.push(value);
  };
  if (filter.speciesId) add('species_id = ?', filter.speciesId);
  if (filter.minLengthM != null) add('length_curved_m >= ?', filter.minLengthM);
  if (filter.maxLengthM != null) add('length_curved_m <= ?', filter.maxLengthM);
  if (filter.minWeightKg != null) add('weight_kg >= ?', filter.minWeightKg);
  if (filter.maxWeightKg != null) add('weight_kg <= ?', filter.maxWeightKg);
  if (filter.createdAfter != null) add('created_at >= ?', filter.createdAfter);
  if (filter.createdBefore != null) add('created_at <= ?', filter.createdBefore);
  if (filter.search) add('LOWER(notes) LIKE ?', `%${filter.search.toLowerCase()}%`);
  const orderBy: Record<CatchSort, string> = {
    newest: 'created_at DESC',
    oldest: 'created_at ASC',
    longest: 'length_curved_m DESC',
    heaviest: 'weight_kg DESC',
  };
  values.push(limit, offset);
  const sql = `SELECT * FROM catches ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
    ORDER BY ${orderBy[sort]} LIMIT ? OFFSET ?`;
  const db = await getDatabase();
  return db.getAllAsync<CatchRecord>(sql, values);
}
