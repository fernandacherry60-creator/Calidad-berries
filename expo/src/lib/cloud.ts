import 'react-native-url-polyfill/auto';
import { createClient } from '@supabase/supabase-js';
import * as SecureStore from 'expo-secure-store';
import { AppState } from 'react-native';

const url = process.env.EXPO_PUBLIC_SUPABASE_URL;
const key = process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

if (!url || !key) {
  throw new Error(
    'Falta configurar EXPO_PUBLIC_SUPABASE_URL y EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY en el entorno de Expo.',
  );
}

const storage = {
  getItem: (key: string) => SecureStore.getItemAsync(key),
  setItem: (key: string, value: string) => SecureStore.setItemAsync(key, value),
  removeItem: (key: string) => SecureStore.deleteItemAsync(key),
};
export const supabase = createClient(url, key, {
  auth: { storage, autoRefreshToken: true, persistSession: true, detectSessionInUrl: false },
});
AppState.addEventListener('change', (state) => {
  if (state === 'active') supabase.auth.startAutoRefresh();
  else supabase.auth.stopAutoRefresh();
});
export type Profile = {
  user_id: string; email: string; display_name: string;
  puesto: string; role: 'admin' | 'trabajador'; active: boolean;
};
export async function loadProfile(userId: string): Promise<Profile | null> {
  const { data, error } = await supabase.from('cb_profiles').select('*')
    .eq('user_id', userId).maybeSingle();
  if (error) throw error;
  return data as Profile | null;
}
export async function redeemPendingInvitation(email: string) {
  const { getPending, clearPending } = await import('./offline');
  const pending = await getPending();
  if (!pending || pending.email !== email.toLowerCase()) return false;
  const { data, error } = await supabase.rpc('cb_redeem_invitation', {
    p_code: pending.code, p_display_name: pending.name, p_puesto: pending.puesto,
  });
  if (error) throw error;
  if (data === true) await clearPending();
  return data === true;
}
