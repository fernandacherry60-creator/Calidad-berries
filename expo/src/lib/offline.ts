import * as SQLite from 'expo-sqlite';
import * as SecureStore from 'expo-secure-store';
import NetInfo from '@react-native-community/netinfo';
import * as FileSystem from 'expo-file-system/legacy';
import { decode } from 'base64-arraybuffer';
import { supabase, type Profile } from './cloud';

export type TableName = 'muestreos_anden' | 'muestreos_proceso' | 'semaforo';
export type LocalSample = { uuid: string; owner_id: string; table_name: TableName; payload: string; fecha: string; synced: number; operation?: 'insert'|'update' };
export type PendingInvite = { email: string; code: string; name: string; puesto: string };
export type Catalogs = { ranchos: string[]; variedades: string[] };
let dbPromise: ReturnType<typeof initializeDatabase> | null = null;
async function initializeDatabase() {
    const connection = await SQLite.openDatabaseAsync('calidad_berries_pro_expo.db');
    await connection.execAsync(`
      PRAGMA journal_mode = WAL;
      CREATE TABLE IF NOT EXISTS samples(
        uuid TEXT PRIMARY KEY,
        owner_id TEXT NOT NULL,
        table_name TEXT NOT NULL,
        payload TEXT NOT NULL,
        fecha TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        operation TEXT NOT NULL DEFAULT 'insert'
      );
      
      CREATE INDEX IF NOT EXISTS samples_owner_pending ON samples(owner_id,synced);
    `);
    const columns=await connection.getAllAsync<{name:string}>('PRAGMA table_info(samples)');
    if(!columns.some(column=>column.name==='operation'))await connection.execAsync("ALTER TABLE samples ADD COLUMN operation TEXT NOT NULL DEFAULT 'insert'");
    return connection;
}
async function db() {
  if (!dbPromise) dbPromise = initializeDatabase().catch(error => { dbPromise = null; throw error; });
  return dbPromise;
}
export async function cacheVerifiedProfile(p: Profile) {
  await SecureStore.setItemAsync('verified_profile', JSON.stringify(p));
}
export async function getCachedProfile(userId: string): Promise<Profile | null> {
  const raw = await SecureStore.getItemAsync('verified_profile');
  if (!raw) return null;
  const profile = JSON.parse(raw) as Profile;
  return profile.user_id === userId && profile.active ? profile : null;
}
export async function getAnyCachedProfile(): Promise<Profile | null> {
  try {
    const raw = await SecureStore.getItemAsync('verified_profile');
    if (!raw) return null;
    const profile = JSON.parse(raw) as Profile;
    return profile?.user_id && profile.active && profile.email ? profile : null;
  } catch {
    return null;
  }
}
export async function cacheCatalogs(catalogs:Catalogs){await SecureStore.setItemAsync('quality_catalogs',JSON.stringify(catalogs));}
export async function getCachedCatalogs():Promise<Catalogs|null>{try{const raw=await SecureStore.getItemAsync('quality_catalogs');if(!raw)return null;const value=JSON.parse(raw) as Catalogs;return Array.isArray(value.ranchos)&&Array.isArray(value.variedades)?value:null;}catch{return null;}}
export async function clearCachedProfile() {
  await SecureStore.deleteItemAsync('verified_profile');
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
export async function cacheRemoteSample(table:TableName,payload:Record<string,unknown>){
  const connection=await db();
  const uuid=String(payload.uuid||'');
  const ownerId=String(payload.owner_id||'');
  if(!uuid||!ownerId)throw new Error('No se puede guardar en caché un muestreo sin identificador o propietario.');
  await connection.runAsync(
    "INSERT INTO samples(uuid,owner_id,table_name,payload,fecha,synced,operation) VALUES (?,?,?,?,?,1,'insert') ON CONFLICT(uuid) DO UPDATE SET table_name=excluded.table_name,payload=excluded.payload,fecha=excluded.fecha,synced=1,operation='insert' WHERE samples.synced=1",
    [uuid,ownerId,table,JSON.stringify(payload),String(payload.fecha||'')],
  );
}
export async function localTeamSamples():Promise<LocalSample[]>{
  const connection=await db();
  return connection.getAllAsync<LocalSample>("SELECT * FROM samples ORDER BY fecha DESC");
}
export async function cacheTeamProfiles(profiles:Profile[]){
  await SecureStore.setItemAsync('quality_team_profiles',JSON.stringify(profiles));
}
export async function getCachedTeamProfiles():Promise<Profile[]>{
  try{const raw=await SecureStore.getItemAsync('quality_team_profiles');if(!raw)return [];const value=JSON.parse(raw);return Array.isArray(value)?value as Profile[]:[];}catch{return [];}
}
export async function updatePendingSample(uuid:string,ownerId:string,payload:Record<string,unknown>){
  const connection=await db();
  const result=await connection.runAsync('UPDATE samples SET payload=? WHERE uuid=? AND owner_id=? AND synced=0',[JSON.stringify(payload),uuid,ownerId]);
  if(result.changes!==1)throw new Error('Solo se pueden modificar registros locales pendientes de sincronización.');
}
export async function updateSyncedSample(table:TableName,uuid:string,ownerId:string,changes:Record<string,unknown>,profile:Profile){
  if(table==='semaforo')throw new Error('Esta edición solo admite andén y proceso.');
  if(!profile.active||ownerId!==profile.user_id&&profile.role!=='admin')throw new Error('No tienes permiso para editar este registro.');
  const connection=await db();
  const row=await connection.getFirstAsync<LocalSample>('SELECT * FROM samples WHERE uuid=? AND owner_id=?',[uuid,ownerId]);
  const updated={...(row?JSON.parse(row.payload):{}),...changes,uuid,owner_id:ownerId};
  const network=await NetInfo.fetch();
  if(row){
    await connection.runAsync("UPDATE samples SET payload=?,synced=0,operation='update' WHERE uuid=? AND owner_id=?",[JSON.stringify(updated),uuid,ownerId]);
    if(network.isConnected&&network.isInternetReachable!==false)await syncSamples(profile);
    return;
  }
  if(!network.isConnected||network.isInternetReachable===false)throw new Error('Este muestreo todavía no está guardado en el teléfono. Conéctate una vez para descargarlo y después podrás editarlo sin conexión.');
  const {data:{user},error:authError}=await supabase.auth.getUser();
  if(authError||!user||user.id!==profile.user_id)throw new Error('Sesión no válida para editar el registro.');
  const {uuid:_uuid,owner_id:_owner,fotos_locales:_localPhotos,...fields}=changes;
  const {data,error}=await supabase.from(table).update(fields).eq('uuid',uuid).eq('owner_id',ownerId).select('uuid').maybeSingle();
  if(error)throw error;
  if(!data)throw new Error('No se actualizó el registro; comprueba los permisos.');
}

export async function pendingCount(ownerId: string, includeAll=false) {
  const connection = await db();
  const result = includeAll
    ? await connection.getFirstAsync<{ total: number }>('SELECT COUNT(*) AS total FROM samples WHERE synced=0')
    : await connection.getFirstAsync<{ total: number }>('SELECT COUNT(*) AS total FROM samples WHERE owner_id=? AND synced=0',[ownerId]);
  return result?.total ?? 0;
}
export async function localSamples(ownerId: string): Promise<LocalSample[]> {
  const connection = await db();
  return connection.getAllAsync<LocalSample>(
    'SELECT * FROM samples WHERE owner_id=? ORDER BY fecha DESC LIMIT 300',[ownerId]);
}
let syncing = false;
export async function syncSamples(profile: Profile): Promise<{ uploaded: number; pending: number }> {
  const network = await NetInfo.fetch();
  if (!network.isConnected || network.isInternetReachable === false) return { uploaded: 0, pending: await pendingCount(profile.user_id,profile.role==='admin') };
  if (syncing) return { uploaded: 0, pending: await pendingCount(profile.user_id,profile.role==='admin') };
  const { data: { user }, error: userError } = await supabase.auth.getUser();
  if (userError) throw userError;
  if (!user || user.id !== profile.user_id || !profile.active) return { uploaded: 0, pending: await pendingCount(profile.user_id,profile.role==='admin') };
  syncing = true;
  let uploaded = 0;
  try {
    const connection = await db();
    while (true) {
      const rows = profile.role==='admin'
        ? await connection.getAllAsync<LocalSample>("SELECT * FROM samples WHERE synced=0 ORDER BY fecha ASC LIMIT 100")
        : await connection.getAllAsync<LocalSample>("SELECT * FROM samples WHERE owner_id=? AND synced=0 ORDER BY fecha ASC LIMIT 100",[user.id]);
      if (rows.length === 0) break;
      for (const row of rows) {
        // owner_id, nombre y correo nunca proceden de entradas editables.
        const payload = JSON.parse(row.payload) as Record<string, unknown>;
        const localPhotos=Array.isArray(payload.fotos_locales)?payload.fotos_locales.filter((v):v is string=>typeof v==='string'):[];
        const storedPhotos=Array.isArray(payload.fotos_json)?payload.fotos_json.filter((v):v is string=>typeof v==='string'):[];
        const uploadedPhotos:string[]=[];
        for(let i=0;i<localPhotos.length;i++){
          const uri=localPhotos[i];
          const base64=await FileSystem.readAsStringAsync(uri,{encoding:FileSystem.EncodingType.Base64});
          if(!base64)throw new Error('No se pudo leer una fotografía guardada en el teléfono.');
          const extension=uri.split('?')[0].split('.').pop()?.toLowerCase()||'jpg';
          const mime=extension==='png'?'image/png':extension==='webp'?'image/webp':extension==='heic'?'image/heic':extension==='heif'?'image/heif':'image/jpeg';
          const normalizedExtension=extension==='jpeg'?'jpg':extension;
          const path=user.id+'/'+row.uuid+'/'+i+'.'+normalizedExtension;
          const {error:photoError}=await supabase.storage.from('evidencias-muestreos').upload(path,decode(base64),{contentType:mime,upsert:true});
          if(photoError)throw photoError;
          uploadedPhotos.push(path);
        }
        const {fotos_locales:_localPhotos,...basePayload}=payload;
        const sanitized = {
          ...basePayload, uuid:row.uuid, fotos_json:[...new Set([...storedPhotos,...uploadedPhotos])], owner_id: row.owner_id, usuario_email: row.operation==='update'?String(basePayload.usuario_email||profile.email):profile.email,
          usuario_nombre: row.operation==='update'?String(basePayload.usuario_nombre||profile.display_name):profile.display_name,
          usuario_puesto: row.operation==='update'?String(basePayload.usuario_puesto||profile.puesto):profile.puesto,
        };
        if(row.operation==='update'){
          const {uuid:_uuid,owner_id:_owner,...fields}=sanitized;
          const {data,error}=await supabase.from(row.table_name).update(fields).eq('uuid',row.uuid).eq('owner_id',row.owner_id).select('uuid').maybeSingle();
          if(error)throw error;
          if(!data)throw new Error('No se pudo sincronizar la edición del registro '+row.uuid);
        }else{
          if(row.owner_id!==user.id)throw new Error('No se permite crear un registro a nombre de otro trabajador.');
          const { error } = await supabase.from(row.table_name).insert({...sanitized,owner_id:user.id});
          if (error) {
            if (error.code !== '23505') throw error;
            const check = await supabase.from(row.table_name).select('uuid').eq('uuid',row.uuid).eq('owner_id',user.id).maybeSingle();
            if (check.error) throw check.error;
            if (!check.data) throw new Error('No se pudo confirmar un registro duplicado: '+row.uuid);
          }
        }
        await connection.runAsync("UPDATE samples SET synced=1,operation='insert' WHERE uuid=? AND owner_id=?",[row.uuid,row.owner_id]);
        uploaded++;
      }
    }
  } finally { syncing = false; }
  return { uploaded, pending: await pendingCount(profile.user_id,profile.role==='admin') };
}
