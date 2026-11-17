import * as SQLite from 'expo-sqlite';
import * as SecureStore from 'expo-secure-store';
import { supabase, type Profile } from './cloud';

export type TableName = 'muestreos_anden' | 'muestreos_proceso' | 'semaforo';
export type LocalSample = { uuid: string; owner_id: string; table_name: TableName; payload: string; fecha: string; synced: number };
export type PendingInvite = { email: string; code: string; name: string; puesto: string };
let dbPromise: ReturnType<typeof SQLite.openDatabaseAsync> | null = null;
async function db() {
  if (!dbPromise) {
    dbPromise = SQLite.openDatabaseAsync('calidad_berries_pro_expo.db');
    const connection = await dbPromise;
    await connection.execAsync(`
      PRAGMA journal_mode = WAL;
      CREATE TABLE IF NOT EXISTS samples(
        uuid TEXT PRIMARY KEY,
        owner_id TEXT NOT NULL,
        table_name TEXT NOT NULL,
        payload TEXT NOT NULL,
        fecha TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      );
      CREATE INDEX IF NOT EXISTS samples_owner_pending ON samples(owner_id,synced);
    `);
  }
  return dbPromise;
}
export async function savePending(p: PendingInvite) {
  await SecureStore.setItemAsync('pending_invite', JSON.stringify(p));
}
export async function getPending(): Promise<PendingInvite | null> {
  const raw = await SecureStore.getItemAsync('pending_invite');
  return raw ? JSON.parse(raw) as PendingInvite : null;
}
export async function clearPending() { await SecureStore.deleteItemAsync('pending_invite'); }
export async function saveSample(table: TableName, payload: Record<string, unknown>, ownerId: string) {
  const connection = await db();
  await connection.runAsync(
    'INSERT INTO samples(uuid,owner_id,table_name,payload,fecha,synced) VALUES (?,?,?,?,?,0)',
    [String(payload.uuid),ownerId,table,JSON.stringify(payload),String(payload.fecha)],
  );
}
export async function pendingCount(ownerId: string) {
  const connection = await db();
  const result = await connection.getFirstAsync<{ total: number }>(
    'SELECT COUNT(*) AS total FROM samples WHERE owner_id=? AND synced=0',[ownerId]);
  return result?.total ?? 0;
}
export async function localSamples(ownerId: string): Promise<LocalSample[]> {
  const connection = await db();
  return connection.getAllAsync<LocalSample>(
    'SELECT * FROM samples WHERE owner_id=? ORDER BY fecha DESC LIMIT 300',[ownerId]);
}
let syncing = false;
export async function syncSamples(profile: Profile): Promise<{ uploaded: number; pending: number }> {
  if (syncing) return { uploaded: 0, pending: await pendingCount(profile.user_id) };
  const { data: { user } } = await supabase.auth.getUser();
  if (!user || user.id !== profile.user_id || !profile.active) return { uploaded: 0, pending: await pendingCount(profile.user_id) };
  syncing = true;
  let uploaded = 0;
  try {
    const connection = await db();
    const rows = await connection.getAllAsync<LocalSample>(
      'SELECT * FROM samples WHERE owner_id=? AND synced=0 ORDER BY fecha ASC LIMIT 100',[user.id]);
    for (const row of rows) {
      // owner_id, nombre y correo nunca proceden de entradas editables.
      const payload = JSON.parse(row.payload) as Record<string, unknown>;
      const sanitized = {
        ...payload, owner_id: user.id, usuario_email: profile.email,
        usuario_nombre: profile.display_name, usuario_puesto: profile.puesto,
      };
      const { error } = await supabase.from(row.table_name).insert(sanitized);
      if (error) {
        if (error.code !== '23505') continue;
        // Confirmar existencia de la muestra bajo RLS antes de marcarla enviada.
        const check = await supabase.from(row.table_name).select('uuid')
          .eq('uuid',row.uuid).eq('owner_id',user.id).maybeSingle();
        if (check.error || !check.data) continue;
      }
      await connection.runAsync('UPDATE samples SET synced=1 WHERE uuid=? AND owner_id=?',[row.uuid,user.id]);
      uploaded++;
    }
  } finally { syncing = false; }
  return { uploaded, pending: await pendingCount(profile.user_id) };
}
