import React, { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Alert, AppState, Image, Modal, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import * as Updates from 'expo-updates';
import * as ImagePicker from 'expo-image-picker';
import * as FileSystem from 'expo-file-system/legacy';
import * as Sharing from 'expo-sharing';
import * as XLSX from 'xlsx';
import * as Linking from 'expo-linking';
import * as Crypto from 'expo-crypto';
import NetInfo from '@react-native-community/netinfo';
import { supabase, loadProfile, redeemPendingInvitation, type Profile } from './src/lib/cloud';
import { savePending, saveSample, updatePendingSample, updateSyncedSample, syncSamples, localSamples, pendingCount, cacheVerifiedProfile, getCachedProfile, getAnyCachedProfile, clearCachedProfile, cacheCatalogs, getCachedCatalogs, type TableName, type LocalSample } from './src/lib/offline';
import { andenDefects, procesoDefects, scoreAnden, scoreProceso, ranchos, variedades, presentaciones, puestos, canastosPorCajas } from './src/lib/rules';

type Screen = 'home'|'team'|'history'|'anden'|'proceso'|'cultivos'|'calculadora'|'pesos'|'informes'|'catalogos';
const C = { ink:'#502027', green:'#A52A35', cream:'#FFF9F3', muted:'#80636A', line:'#E8CBA3', white:'#FFFFFF', danger:'#B71C32', gold:'#BD8A30', burgundy:'#651B2B' };
const fieldStyle = { borderWidth:1,borderColor:C.line,borderRadius:10,padding:9,backgroundColor:C.white,fontSize:14,color:C.ink,fontStyle:'italic' } as const;
const compactFieldStyle = { ...fieldStyle, borderRadius:8, paddingVertical:6, paddingHorizontal:8, fontSize:13 };
const processColor = (pct:number|null) => pct===null?'#80636A':pct<=5?'#16803C':pct<10?'#BD8A30':C.danger;
const processLabel = (pct:number|null) => pct===null?'Sin calcular':pct<=5?'ÓPTIMO':pct<10?'PRECAUCIÓN':'ALTO';
const Button = ({title,onPress,disabled=false}: {title:string;onPress:()=>void;disabled?:boolean}) =>
  <Pressable disabled={disabled} onPress={onPress} style={[styles.button,disabled&&{opacity:.5}]}><Text style={styles.buttonText}>{title}</Text></Pressable>;
const Input = ({label,value,onChange,secure=false,keyboard='default',compact=false}: {label:string;value:string;onChange:(v:string)=>void;secure?:boolean;keyboard?:'default'|'numeric'|'email-address';compact?:boolean}) =>
  <View style={{marginBottom:compact?7:12}}><Text style={[styles.label,compact&&{fontSize:12,marginBottom:3}]}>{label}</Text><TextInput autoCapitalize={keyboard==='email-address'?'none':'sentences'} secureTextEntry={secure} keyboardType={keyboard} style={compact?compactFieldStyle:fieldStyle} value={value} onChangeText={onChange}/></View>;
const ModuleTile = ({icon,title,description,onPress}:{icon:string;title:string;description:string;onPress:()=>void}) =>
  <Pressable accessibilityRole="button" onPress={onPress} style={styles.moduleTile}><Text style={styles.moduleIcon}>{icon}</Text><View style={{flex:1}}><Text style={styles.moduleTitle}>{title}</Text><Text style={styles.moduleDescription}>{description}</Text></View><Text style={styles.moduleArrow}>›</Text></Pressable>;
const Choice = ({label,options,value,onChange,compact=false}: {label:string;options:string[];value:string;onChange:(v:string)=>void;compact?:boolean}) => {
  const [expanded,setExpanded]=useState(false);
  return <View style={{marginBottom:compact?7:12}}>
    <Text style={[styles.label,compact&&{fontSize:12,marginBottom:3}]}>{label}</Text>
    <Pressable accessibilityRole="button" accessibilityLabel={label+': '+value} accessibilityState={{expanded}} onPress={()=>setExpanded(open=>!open)} style={[styles.dropdownHeader,compact&&{borderRadius:9,paddingVertical:9,paddingHorizontal:11}]}>
      <Text style={[styles.dropdownValue,compact&&{fontSize:13}]}>{value||'Seleccionar'}</Text><Text style={[styles.dropdownArrow,compact&&{fontSize:18}]}>{expanded?'▴':'▾'}</Text>
    </Pressable>
    {expanded&&<View style={styles.dropdownOptions}>{options.map(v=><Pressable key={v} accessibilityRole="button" accessibilityState={{selected:value===v}} onPress={()=>{onChange(v);setExpanded(false);}} style={[styles.dropdownOption,value===v&&styles.dropdownOptionSelected,compact&&{paddingVertical:9,paddingHorizontal:11}]}><Text style={[styles.dropdownOptionText,value===v&&{color:C.burgundy,fontWeight:'700'},compact&&{fontSize:13}]}>{v}</Text>{value===v&&<Text style={{color:C.gold}}>✓</Text>}</Pressable>)}</View>}
  </View>;
};
const errorMessage = (e:unknown):string => {
  if(e instanceof Error)return e.message;
  if(typeof e==='string')return e;
  if(e&&typeof e==='object'){
    const value=e as Record<string,unknown>;
    for(const key of ['message','error_description','details','hint','code']){
      if(typeof value[key]==='string'&&value[key])return String(value[key]);
    }
    try{return JSON.stringify(e);}catch{return 'Error desconocido';}
  }
  return String(e);
};
const n = (v:string) => Number(v.replace(',','.'))||0;
const nonNegative = (v:number) => Number.isFinite(v)&&v>=0;
const identity = (profile:Profile) => ({usuario_email:profile.email,usuario_nombre:profile.display_name,usuario_puesto:profile.puesto});
async function handleAuthLink(url:string):Promise<boolean> {
  const params=new URLSearchParams([url.split('?')[1]?.split('#')[0]||'',url.split('#')[1]||''].filter(Boolean).join('&'));
  const error=params.get('error_description');if(error)throw new Error(error);
  const recovery=['recovery','invite'].includes(params.get('type')||'');
  const access=params.get('access_token'),refresh=params.get('refresh_token'),code=params.get('code');
  if(access&&refresh){const {error}=await supabase.auth.setSession({access_token:access,refresh_token:refresh});if(error)throw error;}
  else if(code){const {error}=await supabase.auth.exchangeCodeForSession(code);if(error)throw error;}
  return recovery;
}

async function withDeadline<T>(work:PromiseLike<T>,ms:number):Promise<T>{
  let timer:ReturnType<typeof setTimeout>|undefined;
  try{return await Promise.race([Promise.resolve(work),new Promise<T>((_,reject)=>{timer=setTimeout(()=>reject(new Error('Tiempo de espera agotado')),ms);})]);}
  finally{if(timer!==undefined)clearTimeout(timer);}
}
export default function App() {
  const [profile,setProfile]=useState<Profile|null>(null);
  const [userId,setUserId]=useState<string|null>(null);
  const [busy,setBusy]=useState(true);
  const [recovering,setRecovering]=useState(false);
  const [screen,setScreen]=useState<Screen>('cultivos');
  const [editing,setEditing]=useState<LocalSample|null>(null);
  const [panel,setPanel]=useState<'admin'|'worker'>('admin');
  const [pending,setPending]=useState(0);
  const [isOnline,setIsOnline]=useState(true);
  const [features,setFeatures]=useState<Record<string,boolean>>({enable_sampling:true,enable_cloud_sync:true});
  // Aplicar automáticamente las OTA pendientes al iniciar Android Preview.
  // La publicación está filtrada a Android desde GitHub Actions.
  useEffect(()=>{
    if(Platform.OS!=='android'||__DEV__||!Updates.isEnabled)return;
    let cancelled=false;
    const applyAvailableUpdate=async()=>{
      try{
        const result=await Updates.checkForUpdateAsync();
        if(!result.isAvailable||cancelled)return;
        await Updates.fetchUpdateAsync();
        if(!cancelled)await Updates.reloadAsync();
      }catch(error){
        console.warn('Actualización OTA Android',errorMessage(error));
      }
    };
    void applyAvailableUpdate();
    return ()=>{cancelled=true;};
  },[]);
  useEffect(()=>{
    let alive=true;
    NetInfo.fetch().then(state=>{if(alive)setIsOnline(!!state.isConnected&&state.isInternetReachable!==false);}).catch(()=>{if(alive)setIsOnline(false);});
    const unsubscribe=NetInfo.addEventListener(state=>setIsOnline(!!state.isConnected&&state.isInternetReachable!==false));
    return ()=>{alive=false;unsubscribe();};
  },[]);
  const refresh=useCallback(async()=>{
    let cached:Profile|null=null;
    try { cached=await getAnyCachedProfile(); } catch { cached=null; }
    let session=null;
    try {
      const result=await withDeadline(supabase.auth.getSession(),5000);
      session=result.data.session;
    } catch (error) {
      if(cached?.active){
        setUserId(cached.user_id);setProfile(cached);
        void pendingCount(cached.user_id).then(setPending).catch(()=>{});
        return;
      }
      throw error;
    }
    const user=session?.user;
    if(!user){
      if(cached?.active){
        setUserId(cached.user_id);setProfile(cached);
        void pendingCount(cached.user_id).then(setPending).catch(()=>{});
      }else{setUserId(null);setProfile(null);}
      return;
    }
    setUserId(user.id);
    const userCached=await getCachedProfile(user.id);
    if(userCached){setProfile(userCached);setBusy(false);}
    let p:Profile|null=null;
    try {
      const {data:validated,error:authError}=await withDeadline(supabase.auth.getUser(),5000);
      if(authError){
        if(authError.status===401||authError.status===403){
          await clearCachedProfile();setProfile(null);setUserId(null);return;
        }
        throw authError;
      }
      if(!validated.user||validated.user.id!==user.id){
        await clearCachedProfile();setProfile(null);setUserId(null);return;
      }
      p=await withDeadline(loadProfile(user.id),5000);
      if(!p&&user.email){
        await withDeadline(redeemPendingInvitation(user.email),5000);
        p=await withDeadline(loadProfile(user.id),5000);
      }
      if(p?.active)await cacheVerifiedProfile(p);
      else await clearCachedProfile();
    }catch(error){
      p=userCached?.active?userCached:(cached?.user_id===user.id?cached:null);
    }
    setProfile(p?.active?p:null);
    if(p?.active)void pendingCount(p.user_id).then(setPending).catch(()=>{});
  },[]);
  useEffect(()=>{
    let alive=true;
    (async()=>{try{
      const initial=await withDeadline(Linking.getInitialURL(),2000).catch(()=>null);if(initial)setRecovering(await withDeadline(handleAuthLink(initial),8000));
      await refresh();
    }catch(e){console.warn('Inicio',errorMessage(e));}finally{if(alive)setBusy(false);}})();
    const link=Linking.addEventListener('url',({url})=>{handleAuthLink(url).then(async recovery=>{if(recovery)setRecovering(true);await refresh();}).catch(e=>Alert.alert('Enlace',errorMessage(e)));});
    const auth=supabase.auth.onAuthStateChange((event)=>{if(event==='SIGNED_IN'||event==='SIGNED_OUT'||event==='USER_UPDATED')setTimeout(()=>{refresh().catch(()=>{});},0);});
    return ()=>{alive=false;link.remove();auth.data.subscription.unsubscribe();};
  },[refresh]);
  useEffect(()=>{
    if(!profile)return;
    let active=true;
    const sync=async()=>{
      try {
        const network=await NetInfo.fetch();
        if(network.isConnected){
          await syncSamples(profile);
          const {data}=await supabase.from('cb_app_config').select('value').eq('key','features').maybeSingle();
          if(active&&data?.value)setFeatures(data.value as Record<string,boolean>);
        }
        if(active)setPending(await pendingCount(profile.user_id));
      }catch(e){console.warn('Sincronización pendiente',errorMessage(e));}
    };
    void sync();
    const net=NetInfo.addEventListener(state=>{if(state.isConnected)void sync();});
    const app=AppState.addEventListener('change',state=>{if(state==='active')void sync();});
    return ()=>{active=false;net();app.remove();};
  },[profile]);
  async function logout(){
    try{await supabase.auth.signOut({scope:'local'});}
    catch(e){Alert.alert('Cerrar sesión',errorMessage(e));}
    finally{await clearCachedProfile();setProfile(null);setUserId(null);setScreen('cultivos');}
  }
  if(busy)return <View style={styles.center}><Image source={require("./assets/QUALYX-logo-v2.png")} style={{width:270,height:270}} resizeMode="contain" accessibilityLabel="QUALYX Control de Calidad Berries"/><ActivityIndicator color={C.green} size="large"/></View>;
  if(recovering)return <ResetPasswordView onComplete={async()=>{setRecovering(false);await supabase.auth.signOut();await refresh();}}/>;
  if(!userId||!profile)return <AuthView userId={userId} onDone={refresh} onLogout={logout} onPanel={setPanel}/>;
  const dualPanel=profile.role==='admin'&&profile.email.toLowerCase()==='yamilethklunder@gmail.com';
  const adminPanel=profile.role==='admin'&&(!dualPanel||panel==='admin');
  const navigate=(next:Screen)=>{
    if(!adminPanel&&(next==='team'||next==='informes')){Alert.alert('Acceso restringido','Esta sección está disponible únicamente para administración.');return;}
    if(next==='anden'||next==='proceso')setEditing(null);
    setScreen(next);
  };
  const openEdit=(row:LocalSample)=>{setEditing(row);setScreen(row.table_name==='muestreos_anden'?'anden':'proceso');};
  return <View style={styles.page}>
    <View style={styles.top}><Text style={styles.topTitle}>QUALYX</Text><Text style={styles.topSmall}>{profile.display_name} · {adminPanel?'Administradora':'Trabajadora'}</Text></View>
    <View style={{paddingHorizontal:16,paddingVertical:8,backgroundColor:isOnline?'#E6F4E9':'#FFF0DC'}}><Text style={{fontSize:12,fontWeight:'700',color:isOnline?'#17663B':'#8A4B12'}}>{isOnline?(pending>0?'En línea · '+pending+' pendiente(s) por sincronizar':'En línea · sincronización disponible'):'Sin internet · los muestreos se guardan en este teléfono y se enviarán al reconectar'}</Text></View>
    <ScrollView contentContainerStyle={styles.body}>
      {screen!=='home'&&<Pressable onPress={()=>navigate('home')}><Text style={styles.back}>‹ Volver al inicio</Text></Pressable>}
      {screen==='cultivos'&&<><Text style={styles.heading}>QUALYX · Cultivos</Text><Text style={styles.subtitle}>Selecciona el cultivo a muestrear</Text><Button title="🍓 Frambuesa · disponible" onPress={()=>navigate('home')}/></>}
      {screen==='home'&&<>
        {dualPanel&&<Choice label="Vista de trabajo" options={['Administradora','Trabajadora']} value={panel==='admin'?'Administradora':'Trabajadora'} onChange={v=>{setPanel(v==='Administradora'?'admin':'worker');setScreen('home');}}/>}
        <Text style={styles.heading}>{adminPanel?'Panel de administración':'Panel de trabajador'}</Text>
        <Text style={styles.subtitle}>{adminPanel?'Supervisa personal, muestreos y resultados de calidad':'Captura tus muestreos y consulta tus registros'}</Text>
        <View style={styles.card}><Text style={styles.label}>Registros pendientes en este teléfono</Text><Text style={styles.big}>{pending}</Text>
          <Button title="Sincronizar ahora" onPress={async()=>{try{const r=await syncSamples(profile);setPending(r.pending);Alert.alert('Sincronización',`Subidos: ${r.uploaded}. Pendientes: ${r.pending}`);}catch(e){Alert.alert('Sin conexión',errorMessage(e));}}}/></View>
        {adminPanel&&<>
          <Text style={styles.section}>Administración y supervisión</Text>
          <ModuleTile icon="👥" title="Trabajadores y muestreos en la nube" description="Gestionar personal y consultar registros sincronizados" onPress={()=>navigate('team')}/>
          <ModuleTile icon="📊" title="Informes de calidad" description="Consultar resultados y estadísticas de calidad" onPress={()=>navigate('informes')}/>
          <ModuleTile icon="🌱" title="Catálogos" description="Administrar ranchos y variedades disponibles" onPress={()=>navigate('catalogos')}/>
        </>}
        <Text style={styles.section}>{adminPanel?'Herramientas de muestreo':'Captura de calidad'}</Text>
        {features.enable_sampling!==false&&<><ModuleTile icon="🚚" title="Andenes" description="Recepción, condición, apariencia y disposición" onPress={()=>navigate('anden')}/><ModuleTile icon="⚗️" title="Fruta proceso" description="Defectos, áreas de enfoque y porcentaje de proceso" onPress={()=>navigate('proceso')}/></>}
        
        <ModuleTile icon="🧮" title="Calculadora de defectos" description="Porcentajes de la muestra sin guardar" onPress={()=>navigate('calculadora')}/>
        <ModuleTile icon="⚖️" title="Pesos de clamshells" description="Verificar rangos por presentación" onPress={()=>navigate('pesos')}/>
        <ModuleTile icon="🕘" title="Mi historial de este teléfono" description="Consultar y editar tus muestreos guardados" onPress={()=>navigate('history')}/>
        <Pressable onPress={logout}><Text style={styles.logout}>Cerrar sesión</Text></Pressable>
      </>}
      {screen==='team'&&adminPanel&&<TeamView onEdit={openEdit}/>}
      {screen==='calculadora'&&<CalculatorView/>}
      {screen==='pesos'&&<WeightsView/>}
      {screen==='informes'&&adminPanel&&<ReportsView/>}
      {screen==='catalogos'&&adminPanel&&<CatalogsView/>}
      {screen==='history'&&<HistoryView profile={profile} onEdit={openEdit}/>}
      {(screen==='anden'||screen==='proceso')&&<CaptureView kind={screen} profile={profile} editing={editing} onSaved={async()=>{setEditing(null);setPending(await pendingCount(profile.user_id));navigate('home');}}/>}
    </ScrollView>
  </View>;
}
function AuthView({userId,onDone,onLogout,onPanel}:{userId:string|null;onDone:()=>Promise<void>;onLogout:()=>Promise<void>;onPanel:(v:'admin'|'worker')=>void}) {
  const [selected,setSelected]=useState<'admin'|'worker'|null>(null);
  const [email,setEmail]=useState('');
  const [password,setPassword]=useState('');
  const [working,setWorking]=useState(false);
  async function submit(){
    if(!selected)return;
    setWorking(true);
    try{
      const normalized=email.trim().toLowerCase();
      {
        const {data,error}=await supabase.auth.signInWithPassword({email:normalized,password});
        if(error)throw error;
        const signedUser=data.user;
        if(!signedUser)throw new Error('No se pudo verificar la cuenta');
        let verified=await loadProfile(signedUser.id);
        if(!verified&&selected==='worker'){
          await redeemPendingInvitation(normalized);
          verified=await loadProfile(signedUser.id);
        }
        if(!verified?.active){
          await supabase.auth.signOut();
          throw new Error('Tu cuenta aún no tiene un perfil activo. Confirma tu correo o solicita una invitación.');
        }
        const dual=verified.role==='admin'&&normalized==='yamilethklunder@gmail.com';
        if(selected==='admin'&&verified.role!=='admin'){
          await supabase.auth.signOut();
          throw new Error('Esta cuenta no tiene permiso para el panel de administrador.');
        }
        if(selected==='worker'&&verified.role!=='trabajador'&&!dual){
          await supabase.auth.signOut();
          throw new Error('Esta cuenta no tiene permiso para el panel de trabajador.');
        }
        onPanel(selected);
        await onDone();
      }

    }catch(e){Alert.alert('No se pudo continuar',errorMessage(e));}finally{setWorking(false);}
  }
  return <ScrollView contentContainerStyle={styles.entryPage} keyboardShouldPersistTaps="handled">
    <View style={styles.entryCenter}>
      <Image source={require("./assets/frutas-sin-fondo.png")} style={styles.entryFruitLogo} resizeMode="contain" accessibilityLabel="Frutas QUALYX"/>
      <Text style={styles.entryBrand}>QUALYX</Text>
      <Text style={styles.entryBrandPro}>Control de Calidad Berries</Text>
      <View style={styles.entryRule}/>
      {selected===null?<>
        <Pressable style={styles.entryPrimary} onPress={()=>{setSelected('admin');}}>
          <Text style={styles.entryPrimaryText}>Panel de administrador</Text>
        </Pressable>
        <Pressable style={styles.entrySecondary} onPress={()=>{setSelected('worker');}}>
          <Text style={styles.entrySecondaryText}>Panel de trabajador</Text>
        </Pressable>
      </>:<>
        <Pressable onPress={()=>{setSelected(null);setPassword('');}} style={styles.entryBack}><Text style={styles.entryBackText}>‹ Elegir otro panel</Text></Pressable>
        <View style={styles.entryLoginCard}>
          <Text style={styles.entryLoginTitle}>{selected==='admin'?'Panel de administrador':'Panel de trabajador'}</Text>
          <Text style={styles.entryLoginHint}>{'Ingresa tu correo y contraseña para continuar.'}</Text>
          {userId&&<Text style={styles.notice}>Hay una sesión guardada sin perfil validado. Pulsa Cerrar sesión y vuelve a ingresar.</Text>}

          <Input label="Correo electrónico" value={email} onChange={setEmail} keyboard="email-address"/>
          <Input label="Contraseña (mínimo 8 caracteres)" value={password} onChange={setPassword} secure/>
          <Button title={working?'Procesando…':'Ingresar'} disabled={working||password.length<8||!email.includes('@')} onPress={submit}/>
          <Pressable onPress={async()=>{const normalized=email.trim().toLowerCase();if(!normalized.includes('@')){Alert.alert('Recuperar acceso','Escribe primero tu correo electrónico.');return;}setWorking(true);try{const {error}=await supabase.auth.resetPasswordForEmail(normalized,{redirectTo:'calidadberriespro://auth-callback'});if(error)throw error;Alert.alert('Revisa tu correo','Abre el enlace de recuperación en este teléfono y escribe tu nueva contraseña en la aplicación.');}catch(e){Alert.alert('Recuperación',errorMessage(e));}finally{setWorking(false);}}} style={styles.entryRegister}><Text style={styles.entryRegisterText}>Olvidé mi contraseña</Text></Pressable>
          <Button title="Reiniciar sesión en este teléfono" onPress={onLogout}/>
        </View>
      </>}
    </View>
    <Text style={styles.entryFooter}>CONTROL DE CALIDAD  ·  CALIDAD BERRIES PRO</Text>
  </ScrollView>;
}
function ResetPasswordView({onComplete}:{onComplete:()=>Promise<void>}){
  const [password,setPassword]=useState('');
  const [confirm,setConfirm]=useState('');
  const [saving,setSaving]=useState(false);
  return <ScrollView contentContainerStyle={styles.entryPage}><View style={styles.entryCenter}>
    <Text style={styles.entryBrand}>QUALYX</Text><Text style={styles.entryBrandPro}>Control de Calidad Berries</Text>
    <View style={styles.entryLoginCard}><Text style={styles.entryLoginTitle}>Establecer contraseña nueva</Text>
      <Text style={styles.entryLoginHint}>El enlace de recuperación ya abrió una sesión temporal. Guarda aquí tu nueva contraseña.</Text>
      <Input label="Contraseña nueva (mínimo 8 caracteres)" value={password} onChange={setPassword} secure/>
      <Input label="Confirmar contraseña" value={confirm} onChange={setConfirm} secure/>
    <Button title={saving?'Guardando…':'Guardar contraseña'} disabled={saving||password.length<8||password!==confirm} onPress={async()=>{
        setSaving(true);try{const {error}=await supabase.auth.updateUser({password});if(error)throw error;Alert.alert('Contraseña actualizada','Ya puedes iniciar sesión con tu contraseña nueva.',[{text:'Continuar',onPress:()=>void onComplete()}]);}catch(e){Alert.alert('No se pudo actualizar',errorMessage(e));}finally{setSaving(false);}
      }}/>
    </View></View></ScrollView>;
}
function TeamView({onEdit}:{onEdit:(row:LocalSample)=>void}){
  const [members,setMembers]=useState<Profile[]>([]);
  const [samples,setSamples]=useState<Record<string,unknown>[]>([]);
  const [invitation,setInvitation]=useState('');
  const [workerEmail,setWorkerEmail]=useState('');
  const [workerName,setWorkerName]=useState('');
  const [workerPuesto,setWorkerPuesto]=useState(puestos[0]);
  const [loading,setLoading]=useState(false);
  const refresh=useCallback(async()=>{
    try{
      const {data,error}=await supabase.from('cb_profiles').select('*').order('display_name');
      if(error)throw error;setMembers((data||[]) as Profile[]);
      const all:Record<string,unknown>[]=[];
      for(const table of ['muestreos_anden','muestreos_proceso','semaforo'] as TableName[]){
        const result=await supabase.from(table).select('*').order('fecha',{ascending:false}).limit(50);
        if(result.error)throw result.error;
        all.push(...(result.data||[]).map(item=>({...item,tipo:table})));
      }
      all.sort((a,b)=>String(b.fecha).localeCompare(String(a.fecha)));setSamples(all);
    }catch(e){Alert.alert('Consulta',errorMessage(e));}
  },[]);
  useEffect(()=>{void refresh();},[refresh]);
  async function invite(){
    setLoading(true);
    try{
      const {data,error}=await supabase.functions.invoke('cb-invite-worker',{body:{
        email:workerEmail.trim().toLowerCase(),name:workerName.trim(),puesto:workerPuesto
      }});
      if(error)throw error;
      if(data?.error)throw new Error(data.error);
      setInvitation(workerEmail.trim().toLowerCase());
      setWorkerEmail('');setWorkerName('');
      await refresh();
      Alert.alert('Invitación enviada','El trabajador recibirá un correo para establecer su contraseña y activar su acceso.');
    }catch(e){Alert.alert('Invitación',errorMessage(e));}finally{setLoading(false);}
  }
  return <><Text style={styles.heading}>Gestión de trabajadores</Text><Text style={styles.subtitle}>Solo la administradora puede enviar invitaciones. Cada trabajador establece su propia contraseña.</Text><Input label="Nombre completo" value={workerName} onChange={setWorkerName}/><Choice label="Puesto" options={puestos} value={workerPuesto} onChange={setWorkerPuesto}/><Input label="Correo del trabajador" value={workerEmail} onChange={setWorkerEmail} keyboard="email-address"/><Button title={loading?"Enviando…":"Enviar invitación por correo"} disabled={loading||workerName.trim().length<2||!workerEmail.includes("@")} onPress={invite}/><Button title="Actualizar lista" onPress={()=>void refresh()}/>
    {invitation!==""&&<Text style={styles.notice}>Invitación enviada a {invitation}</Text>}
    <Text style={styles.section}>Personal ({members.length})</Text>
    {members.map(m=><View key={m.user_id} style={styles.card}><Text style={styles.label}>{m.display_name} · {m.role}</Text><Text>{m.email} · {m.puesto} · {m.active?'Activo':'Inactivo'}</Text></View>)}
    <Text style={styles.section}>Últimos muestreos en la nube</Text>
    {samples.filter(m=>m.tipo!=='semaforo').map(m=><View key={String(m.uuid)} style={styles.card}><Text style={styles.label}>{String(m.tipo)} · {String(m.cultivo)}</Text><Text>{String(m.usuario_nombre||m.usuario_email||'Sin nombre')}</Text><Text>{String(m.fecha)}</Text>{m.tipo!=='semaforo'&&<Button title="Modificar este muestreo" onPress={()=>onEdit({uuid:String(m.uuid),owner_id:String(m.owner_id),table_name:m.tipo as TableName,payload:JSON.stringify(m),fecha:String(m.fecha),synced:1})}/>}</View>)}
  </>;
}
function CatalogsView(){
  const [ranchosList,setRanchosList]=useState(ranchos),[variedadesList,setVariedadesList]=useState(variedades);
  const [newRancho,setNewRancho]=useState(''),[newVariedad,setNewVariedad]=useState('');
  const [loading,setLoading]=useState(false);
  useEffect(()=>{let active=true;(async()=>{try{const {data,error}=await supabase.from('cb_catalogs').select('ranchos,variedades').eq('id',1).maybeSingle();if(error)throw error;if(active&&data){setRanchosList(data.ranchos||ranchos);setVariedadesList(data.variedades||variedades);}}catch(e){Alert.alert('Catálogos',errorMessage(e));}})();return()=>{active=false;};},[]);
  const save=async(nextRanchos:string[],nextVariedades:string[])=>{setLoading(true);try{const {data,error}=await supabase.from('cb_catalogs').update({ranchos:nextRanchos,variedades:nextVariedades,updated_at:new Date().toISOString()}).eq('id',1).select('id').maybeSingle();if(error)throw error;if(!data)throw new Error('No se guardaron los cambios. Verifica que tu perfil tenga permisos de administración.');const next={ranchos:nextRanchos,variedades:nextVariedades};await cacheCatalogs(next);setRanchosList(nextRanchos);setVariedadesList(nextVariedades);Alert.alert('Catálogos','Cambios guardados. Los teléfonos los descargarán al conectarse.');}catch(e){Alert.alert('No se pudo guardar',errorMessage(e));}finally{setLoading(false);}};
  return <><Text style={styles.heading}>Administración de catálogos</Text><Text style={styles.subtitle}>Los cambios se sincronizan con los teléfonos del equipo.</Text>
    <Text style={styles.section}>Ranchos ({ranchosList.length})</Text><Input label="Agregar rancho" value={newRancho} onChange={setNewRancho}/><Button title="Agregar rancho" disabled={loading||newRancho.trim().length<2||ranchosList.some(x=>x.toLowerCase()===newRancho.trim().toLowerCase())} onPress={()=>{const next=[...ranchosList,newRancho.trim().toUpperCase()];setNewRancho('');void save(next,variedadesList);}}/>
    {ranchosList.map(item=><View key={item} style={{flexDirection:'row',alignItems:'center',justifyContent:'space-between',padding:10,backgroundColor:C.white,borderRadius:10,marginBottom:6}}><Text style={{color:C.ink,flex:1}}>{item}</Text><Button title="Eliminar" disabled={loading||ranchosList.length<=1} onPress={()=>void save(ranchosList.filter(x=>x!==item),variedadesList)}/></View>)}
    <Text style={styles.section}>Variedades ({variedadesList.length})</Text><Input label="Agregar variedad" value={newVariedad} onChange={setNewVariedad}/><Button title="Agregar variedad" disabled={loading||newVariedad.trim().length<2||variedadesList.some(x=>x.toLowerCase()===newVariedad.trim().toLowerCase())} onPress={()=>{const next=[...variedadesList,newVariedad.trim().toUpperCase()];setNewVariedad('');void save(ranchosList,next);}}/>
    {variedadesList.map(item=><View key={item} style={{flexDirection:'row',alignItems:'center',justifyContent:'space-between',padding:10,backgroundColor:C.white,borderRadius:10,marginBottom:6}}><Text style={{color:C.ink,flex:1}}>{item}</Text><Button title="Eliminar" disabled={loading||variedadesList.length<=1} onPress={()=>void save(ranchosList,variedadesList.filter(x=>x!==item))}/></View>)}
  </>;
}
function CalculatorView(){
  const [total,setTotal]=useState('100'),[larvas,setLarvas]=useState('0');
  const [counts,setCounts]=useState<Record<string,string>>({});
  const sample=n(total),larva=n(larvas);
  const values=Object.fromEntries(andenDefects.map(d=>[d.key,n(counts[d.key]||'0')]));
  const counted=Object.values(values).reduce((sum,v)=>sum+v,0);
  const valid=Number.isInteger(sample)&&sample>0&&Number.isInteger(larva)&&larva>=0&&counted<=sample&&andenDefects.every(d=>Number.isInteger(values[d.key])&&values[d.key]>=0);
  const result=valid?scoreAnden(values,sample,larva):null;
  return <><Text style={styles.heading}>Calculadora de defectos</Text><Text style={styles.subtitle}>Simulación Driscoll's · mismos criterios que Andenes · no guarda registros</Text>
    <View style={{flexDirection:'row',gap:10}}><View style={{flex:1}}><Input label="Frutos totales" value={total} onChange={setTotal} keyboard="numeric"/></View><View style={{flex:1}}><Input label="Frutos con larva" value={larvas} onChange={setLarvas} keyboard="numeric"/></View></View>
    {['condicion','apariencia'].map(group=><><Text style={styles.section}>{group==='condicion'?'Condición · límite 5%':'Apariencia · reempaque 15–15.5%, rechazo desde 15.6%'}</Text>
      {andenDefects.filter(d=>d.category===group).map(d=><View key={d.key} style={styles.defectRow}><View style={{flex:1}}><Text style={styles.defectTitle}>{d.label}</Text><Text style={styles.defectCategory}>{sample>0?(values[d.key]/sample*100).toFixed(1)+'%':'—'}</Text></View><Pressable accessibilityLabel={'Restar '+d.label} onPress={()=>setCounts(prev=>({...prev,[d.key]:String(Math.max(0,n(prev[d.key]||'0')-1))}))} style={styles.counterButton}><Text style={styles.counterText}>−</Text></Pressable><Text style={styles.counterValue}>{counts[d.key]||'0'}</Text><Pressable accessibilityLabel={'Sumar '+d.label} onPress={()=>setCounts(prev=>({...prev,[d.key]:String(n(prev[d.key]||'0')+1)}))} style={styles.counterButton}><Text style={styles.counterText}>+</Text></Pressable></View>)}
    </>)}
    <View style={styles.card}><Text style={styles.label}>Frutos contados: {counted} / {sample||0}</Text>{!valid&&<Text style={{color:C.danger}}>Revisa los conteos: deben ser enteros y no superar el total de frutos.</Text>}
      {result&&<><Text style={[styles.big,{color:result.disposicion==='RECHAZO'?C.danger:result.disposicion==='REEMPAQUE'?C.gold:'#16803C'}]}>{result.disposicion}</Text><Text>Condición: {(result.pct_condicion*100).toFixed(1)}% · Apariencia: {(result.pct_apariencia*100).toFixed(1)}%</Text><Text>Puntos: {result.puntos_total}/80 · Larvas: {larva}</Text></>}
      <Button title="Limpiar calculadora" onPress={()=>{setCounts({});setTotal('100');setLarvas('0');}}/></View></>;
}
function WeightsView(){
  const [weight,setWeight]=useState('');
  const value=weight.trim()?Number(weight.replace(',','.')):NaN;
  return <><Text style={styles.heading}>Pesos de clamshells</Text><Text style={styles.subtitle}>Verificación por presentación · gramos</Text>
    <Input label="Peso medido (g)" value={weight} onChange={setWeight} keyboard="numeric"/>
    {presentaciones.map(p=><View key={p.name} style={styles.card}><Text style={styles.label}>{p.name}</Text>
      <Text>Rango: {p.min}–{p.max} g</Text><Text style={{color:Number.isFinite(value)?value>=p.min&&value<=p.max?C.green:C.danger:C.muted}}>{Number.isFinite(value)?value>=p.min&&value<=p.max?'Dentro de rango':'Fuera de rango':'Ingresa un peso'}</Text></View>)}</>;
}
function ReportsView(){
  const [period,setPeriod]=useState('Hoy');
  const [rancho,setRancho]=useState('Todos');
  const [ranchOptions,setRanchOptions]=useState(ranchos);
  useEffect(()=>{let active=true;(async()=>{const cached=await getCachedCatalogs();if(active&&cached)setRanchOptions(cached.ranchos);try{const {data,error}=await supabase.from('cb_catalogs').select('ranchos').eq('id',1).maybeSingle();if(!error&&data&&active){const list=Array.isArray(data.ranchos)?data.ranchos:ranchos;setRanchOptions(list);await cacheCatalogs({ranchos:list,variedades:variedades});}}catch{/* se usa el catálogo local */}})();return()=>{active=false;};},[]);
  const [rows,setRows]=useState<Record<string,unknown>[]>([]);
  const [loading,setLoading]=useState(false),[exporting,setExporting]=useState(false);
  const load=async()=>{
    setLoading(true);
    try{
      const days=period==='Hoy'?1:period==='7 días'?7:30;
      const from=new Date();from.setHours(0,0,0,0);from.setDate(from.getDate()-(days-1));
      const results:Record<string,unknown>[]=[];
      for(const table of ['muestreos_anden','muestreos_proceso'] as const){
        // Ambas tablas no comparten todas las columnas.
        const columns='*';
        let q=supabase.from(table).select(columns).gte('fecha',from.toISOString()).order('fecha',{ascending:false}).limit(500);
        if(rancho!=='Todos')q=q.eq('rancho',rancho);
        const {data,error}=await q;
        if(error)throw error;
        results.push(...((data||[]) as unknown as Record<string,unknown>[]).map(x=>({...x,tabla:table})));
      }
      setRows(results);
    }catch(e){Alert.alert('Informes',errorMessage(e));}finally{setLoading(false);}
  };
  const anden=rows.filter(r=>r.tabla==='muestreos_anden'),proceso=rows.filter(r=>r.tabla==='muestreos_proceso');
  const rejected=anden.filter(r=>r.disposicion==='RECHAZO').length;
  const avg=proceso.length?proceso.reduce((s,r)=>s+Number(r.potencial_empacable||0),0)/proceso.length:0;
  const defectTotals:Record<string,number>={};
  for(const r of rows){
    const values=(r.defectos_json||{}) as Record<string,number>;
    for(const [key,value] of Object.entries(values)){
      if(key==='Fruta buena')continue;
      const label=(r.tabla==='muestreos_anden'?'Andén: ':'Proceso: ')+key;
      defectTotals[label]=(defectTotals[label]||0)+Number(value||0);
    }
  }
  const topDefects=Object.entries(defectTotals).sort((a,b)=>b[1]-a[1]).slice(0,12);
  const exportExcel=async()=>{setExporting(true);try{const book=XLSX.utils.book_new();const andRows=anden.map(r=>({Fecha:r.fecha,Rancho:r.rancho,Sector:r.sector,Cultivo:r.cultivo,Variedad:r.variedad,Presentacion:r.presentacion,Cuadrilla:r.cuadrilla,Licencia:r.licencia,Evaluador:r.evaluador,Embaladora:r.muestreados,Cajas:r.cajas_recibidas,Canastos:r.canastos,Frutos:r.fruta_muestra,Brix:r.grados_brix,Peso:r.peso,Larvas:r.frutos_larva,Condicion:r.pct_condicion,Apariencia:r.pct_apariencia,PuntosCondicion:r.puntos_condicion,PuntosApariencia:r.puntos_apariencia,PuntosTotal:r.puntos_total,Disposicion:r.disposicion,Motivo:r.motivo,Defectos:JSON.stringify(r.defectos_json||{}),Fotos:JSON.stringify(r.fotos_json||[])}));const processRows=proceso.map(r=>({Fecha:r.fecha,Rancho:r.rancho,Cultivo:r.cultivo,Cajas:r.cajas,Taras:r.taras,PorcentajeProceso:r.pct_proceso,FrutosMuestra:r.frutos_muestra,AreaAgronomia:r.area_agronomia,AreaPoscosecha:r.area_poscosecha,AreaCosecha:r.area_cosecha,AreaActividades:r.area_actividades,AreaInocuidad:r.area_inocuidad,TotalDefectos:r.total_defectos,PotencialEmpacable:r.potencial_empacable,Defectos:JSON.stringify(r.defectos_json||{})}));const days=[...new Set([...anden,...proceso].map(r=>String(r.fecha||'').slice(0,10)))].sort();const summaryRows:any[][]=[['REPORTE DE CALIDAD DE BERRIES'],['Generado',new Date().toLocaleString('es-MX')],[],['ANDENES - RESUMEN POR DIA'],['Fecha','Tarimas','Paso','Reempaque','Rechazo','% Rechazo','Puntos promedio']];let sumTarimas=0,sumPaso=0,sumReempaque=0,sumRechazo=0;for(const day of days){const group=anden.filter(r=>String(r.fecha||'').slice(0,10)===day);if(!group.length)continue;const paso=group.filter(r=>r.disposicion==='PASO').length;const reempaque=group.filter(r=>r.disposicion==='REEMPAQUE'||r.disposicion==='PRE-RECHAZO').length;const rechazo=group.filter(r=>r.disposicion==='RECHAZO').length;const points=group.reduce((s,r)=>s+Number(r.puntos_total||0),0)/group.length;sumTarimas+=group.length;sumPaso+=paso;sumReempaque+=reempaque;sumRechazo+=rechazo;summaryRows.push([day,group.length,paso,reempaque,rechazo,Number((rechazo/group.length*100).toFixed(1)),Number(points.toFixed(1))]);}summaryRows.push(['TOTAL',sumTarimas,sumPaso,sumReempaque,sumRechazo,sumTarimas?Number((sumRechazo/sumTarimas*100).toFixed(1)):0,'']);summaryRows.push([],['FRUTA PROCESO - RESUMEN POR DIA'],['Fecha','Muestreos','Potencial empacable promedio (%)']);for(const day of days){const group=proceso.filter(r=>String(r.fecha||'').slice(0,10)===day);if(group.length)summaryRows.push([day,group.length,Number((group.reduce((s,r)=>s+Number(r.potencial_empacable||0),0)/group.length).toFixed(1))]);}if(!anden.length)summaryRows.push(['Sin muestreos de andén en el periodo']);if(!proceso.length)summaryRows.push(['Sin muestreos de proceso en el periodo']);XLSX.utils.book_append_sheet(book,XLSX.utils.aoa_to_sheet(summaryRows),'Resumen');XLSX.utils.book_append_sheet(book,XLSX.utils.json_to_sheet(andRows),'Andenes');XLSX.utils.book_append_sheet(book,XLSX.utils.json_to_sheet(processRows),'Fruta proceso');const base64=XLSX.write(book,{type:'base64',bookType:'xlsx'});const uri=(FileSystem.cacheDirectory||'')+'qualyx_reporte_'+Date.now()+'.xlsx';await FileSystem.writeAsStringAsync(uri,base64,{encoding:FileSystem.EncodingType.Base64});await Sharing.shareAsync(uri,{mimeType:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',dialogTitle:'Exportar reporte QUALYX'});}catch(e){Alert.alert('Exportación Excel',errorMessage(e));}finally{setExporting(false);}};
  const maxDefect=Math.max(1,...topDefects.map(x=>x[1]));
  const daily:Record<string,number>={};
  for(const r of rows){const day=String(r.fecha).slice(0,10);daily[day]=(daily[day]||0)+1;}
  const trend=Object.entries(daily).sort((a,b)=>a[0].localeCompare(b[0]));
  const maxDaily=Math.max(1,...trend.map(x=>x[1]));
  return <><Text style={styles.heading}>Informes de calidad</Text>
    <Choice label="Periodo" options={['Hoy','7 días','30 días']} value={period} onChange={setPeriod}/>
    <Choice label="Rancho" options={['Todos',...ranchOptions]} value={rancho} onChange={setRancho}/>
    <Button title={loading?'Consultando…':'Generar informe'} disabled={loading} onPress={()=>void load()}/><Button title={exporting?'Preparando Excel…':'Exportar Excel · 3 hojas'} disabled={exporting||rows.length===0} onPress={()=>void exportExcel()}/>
    <View style={styles.card}><Text style={styles.label}>Andenes: {anden.length} · Rechazos: {rejected}</Text>
      <Text style={styles.label}>Proceso: {proceso.length} · Potencial empacable promedio: {avg.toFixed(1)}%</Text></View>
    <Text style={styles.section}>Gráfica de defectos más frecuentes</Text>
    {topDefects.length===0&&<Text style={styles.notice}>No hay defectos registrados para el filtro seleccionado.</Text>}
    {topDefects.map(([label,value])=><View key={label} style={{marginBottom:12}}>
      <Text style={styles.label}>{label} · {value.toFixed(1)}</Text>
      <View style={{height:13,backgroundColor:C.line,borderRadius:7,overflow:'hidden'}}><View style={{height:13,width:((value/maxDefect*100)+'%') as `${number}%`,backgroundColor:C.gold,borderRadius:7}}/></View>
    </View>)}
    <Text style={styles.section}>Gráfica de muestreos por día</Text>
    {trend.map(([day,value])=><View key={day} style={{marginBottom:10}}>
      <Text style={styles.label}>{day} · {value} muestreos</Text>
      <View style={{height:13,backgroundColor:C.line,borderRadius:7,overflow:'hidden'}}><View style={{height:13,width:((value/maxDaily*100)+'%') as `${number}%`,backgroundColor:C.green,borderRadius:7}}/></View>
    </View>)}
    {rows.map((r,i)=>{const disposition=String(r.disposicion||'');const isAnden=r.tabla==='muestreos_anden';const statusColor=disposition==='RECHAZO'?C.danger:disposition==='REEMPAQUE'?'#A66B00':'#16803C';const statusBg=disposition==='RECHAZO'?'#FCE4E4':disposition==='REEMPAQUE'?'#FFF3D6':'#E5F3E8';return <View key={String(r.uuid)+String(i)} style={[styles.card,isAnden&&{borderWidth:1,borderColor:statusColor}]}><Text>{isAnden?'Andén':'Proceso'} · {String(r.rancho)}</Text><Text>{String(r.fecha).slice(0,10)}</Text>{isAnden?<Text style={{fontWeight:'900',color:statusColor,backgroundColor:statusBg,padding:8,borderRadius:8,marginTop:5}}>{disposition}</Text>:<Text>Empacable {Number(r.potencial_empacable||0).toFixed(1)}%</Text>}</View>;})}
  </>;
}
function HistoryView({profile,onEdit}:{profile:Profile;onEdit:(row:LocalSample)=>void}){
  const [rows,setRows]=useState<LocalSample[]>([]);
  useEffect(()=>{void localSamples(profile.user_id).then(setRows).catch(e=>Alert.alert('Historial',errorMessage(e)));},[profile.user_id]);
  return <><Text style={styles.heading}>Historial local</Text>{rows.length===0&&<Text>Sin registros en este teléfono</Text>}
    {rows.filter(row=>row.table_name!=='semaforo').map(row=><View key={row.uuid} style={styles.card}><Text style={styles.label}>{row.table_name}</Text><Text>{row.fecha}</Text><Text style={{color:row.synced?C.green:C.danger}}>{row.synced?'Sincronizado':'Pendiente'}</Text>{row.table_name!=='semaforo'&&<Button title="Modificar muestreo" onPress={()=>onEdit(row)}/>}</View>)}</>;
}
function CaptureView({kind,profile,onSaved,editing}:{kind:'anden'|'proceso';profile:Profile;onSaved:()=>Promise<void>;editing:LocalSample|null}){
  const [rancho,setRancho]=useState(ranchos[0]),[sector,setSector]=useState(''),[variedad,setVariedad]=useState(variedades[0]);
  const [licencia,setLicencia]=useState(''),[brix,setBrix]=useState('');
  const [photos,setPhotos]=useState<string[]>([]),[storedPhotoPaths,setStoredPhotoPaths]=useState<string[]>([]);
  const [catalogOptions,setCatalogOptions]=useState({ranchos,variedades});
  const [presentacion,setPresentacion]=useState('6 oz'),[cuadrilla,setCuadrilla]=useState('');
  const [cajas,setCajas]=useState('0'),[taras,setTaras]=useState('0'),[frutos,setFrutos]=useState('100');
  const [larvas,setLarvas]=useState('0'),[peso,setPeso]=useState('');
  const [embaladora,setEmbaladora]=useState(''),[nota,setNota]=useState('');
  const [empacable,setEmpacable]=useState('');
  const [continueAnden,setContinueAnden]=useState(false);
  const [categoria,setCategoria]=useState('Condición'),[nivel,setNivel]=useState('ok');
  const [counts,setCounts]=useState<Record<string,string>>({});
  const [saving,setSaving]=useState(false);
  const [sharePreview,setSharePreview]=useState(false);
  const [step,setStep]=useState(1);
  useEffect(()=>{let active=true;(async()=>{const cached=await getCachedCatalogs();if(active&&cached)setCatalogOptions(cached);try{const {data,error}=await supabase.from('cb_catalogs').select('ranchos,variedades').eq('id',1).maybeSingle();if(!error&&data&&active){const next={ranchos:Array.isArray(data.ranchos)?data.ranchos:ranchos,variedades:Array.isArray(data.variedades)?data.variedades:variedades};setCatalogOptions(next);await cacheCatalogs(next);}}catch{/* se conserva el catálogo local */}})();return()=>{active=false;};},[]);
  const processKg=n(cajas)*2.23+n(taras)*3;
  const liveProcess=processKg>0?n(taras)*3/processKg*100:null;
  const defects=kind==='anden'?andenDefects:procesoDefects;
  const totalPreview=n(frutos);
  const previewCounts=Object.fromEntries(defects.map(d=>[d.key,n(counts[d.key]||'0')]));
  const activeDefects=defects.filter(d=>n(counts[d.key]||'0')>0);
  const countedPreview=Object.values(previewCounts).reduce((sum,value)=>sum+value,0);
  const validPreview=totalPreview>0&&Object.values(previewCounts).reduce((s,v)=>s+v,0)<=totalPreview;
  const andenPreview=kind==='anden'&&validPreview?scoreAnden(previewCounts,totalPreview,n(larvas)):null;
  const procesoPreview=kind==='proceso'&&validPreview?scoreProceso(previewCounts,totalPreview,n(cajas),n(taras),empacable.trim()?n(empacable):undefined):null;
  useEffect(()=>{
    if(!editing)return;
    const p=JSON.parse(editing.payload) as Record<string,unknown>;
    setRancho(String(p.rancho||ranchos[0]));setSector(String(p.sector||''));setVariedad(String(p.variedad||variedades[0]));
    setLicencia(String(p.licencia||''));setBrix(p.grados_brix==null?'':String(p.grados_brix));
    setPhotos(Array.isArray(p.fotos_locales)?p.fotos_locales.filter((v):v is string=>typeof v==='string'):[]);setStoredPhotoPaths(Array.isArray(p.fotos_json)?p.fotos_json.filter((v):v is string=>typeof v==='string'):[]);
    setPresentacion(String(p.presentacion||'6 oz'));setCuadrilla(String(p.cuadrilla||''));
    setCajas(String(p.cajas_recibidas??p.cajas??0));setTaras(String(p.taras??0));
    setFrutos(String(p.fruta_muestra??p.frutos_muestra??100));setLarvas(String(p.frutos_larva??0));
    setPeso(String(p.peso??''));setEmbaladora(String(p.muestreados??''));
    setNota(String(p.motivo??''));setCounts(Object.fromEntries(Object.entries((p.defectos_json||{}) as Record<string,number>).map(([k,v])=>[k,String(editing.table_name==='muestreos_proceso'?Math.round(Number(v)*Number(p.frutos_muestra||100)/100):v)])));
    setEmpacable(p.potencial_empacable==null?'':String(p.potencial_empacable));
  },[editing]);
  async function save(){
    setSaving(true);
    try{
      const total=n(frutos),box=n(cajas),t=n(taras),larva=n(larvas);
      if(!Number.isInteger(total)||total<=0||!Number.isInteger(box)||box<0)throw new Error('Revisa los totales de frutos y cajas');
      if(!nonNegative(t)||!Number.isInteger(t)||!nonNegative(larva)||!Number.isInteger(larva))throw new Error('Los conteos deben ser enteros positivos');
      const defectCounts:Record<string,number>={};
      for(const d of defects){
        const raw=counts[d.key]||'0',value=Number(raw);
        if(!Number.isInteger(value)||value<0)throw new Error('Conteo inválido: '+d.label);
        defectCounts[d.key]=value;
      }
      const uuid=Crypto.randomUUID(),fecha=new Date().toISOString();
      let payload:Record<string,unknown>|null=null;
      let table:TableName|null=null;
      if(kind==='anden'){
        if(Object.values(defectCounts).reduce((a,b)=>a+b,0)>total)throw new Error('Los defectos superan el total de frutos');
        const score=scoreAnden(defectCounts,total,larva);
        payload={uuid,fecha,cultivo:'Frambuesa',rancho,sector,variedad,presentacion,cuadrilla,licencia,grados_brix:brix?n(brix):null,
          cajas_recibidas:box,canastos:canastosPorCajas(box),fruta_muestra:total,
          peso:peso?n(peso):null,frutos_larva:larva,fotos_locales:photos,fotos_json:storedPhotoPaths,
          evaluador:profile.display_name,muestreados:embaladora,defectos_json:defectCounts,
          ...score,motivo:nota,...identity(profile)};
        table='muestreos_anden';
      }else if(kind==='proceso'){
        if(Object.values(defectCounts).reduce((a,b)=>a+b,0)>total)throw new Error('Los defectos superan el total de frutos');
        const manual=empacable.trim()===''?undefined:Number(empacable.replace(',','.'));
        if(manual===undefined||!Number.isFinite(manual)||manual<0||manual>100)throw new Error('Captura el porcentaje empacable manualmente, entre 0 y 100');
        const score=scoreProceso(defectCounts,total,box,t,manual);
        payload={uuid,fecha,cultivo:'Frambuesa',frutos_muestra:total,rancho,presentacion,cuadrilla,muestreados:embaladora,peso:peso?n(peso):null,frutos_larva:larva,cajas:box,taras:t,...score,...identity(profile)};
        table='muestreos_proceso';
      }
      if(!payload||!table)throw new Error('Tipo de muestreo no válido');
      if(editing){
        // Preservar la identidad y la fecha originales para evitar duplicados.
        const original=JSON.parse(editing.payload) as Record<string,unknown>;
        const changes:Record<string,unknown>={...payload,uuid:editing.uuid,fecha:editing.fecha};
        const updated={...original,...changes};
        if(editing.synced){
          const {uuid:_uuid,fecha:_fecha,owner_id:_owner,usuario_email:_email,usuario_nombre:_nombre,usuario_puesto:_puesto,evaluador:_evaluador,...fields}=changes;
          await updateSyncedSample(table,editing.uuid,editing.owner_id,fields,profile);
        }else await updatePendingSample(editing.uuid,profile.user_id,updated);
        Alert.alert('Actualizado','El muestreo se modificó correctamente.');
      }else{
        await saveSample(table,payload,profile.user_id);
        Alert.alert('Guardado','Registro almacenado en el teléfono. Se sincronizará al tener conexión.');
      }
      if(!editing&&kind==='anden'&&continueAnden){
        setStep(1);setCounts({});setLarvas('0');setPeso('');setNota('');
        // Mantener rancho, sector, variedad, presentación, cuadrilla y embaladora.
      }else await onSaved();
    }catch(e){Alert.alert('Revisar captura',errorMessage(e));}finally{setSaving(false);}
  }
  return <><Text style={styles.heading}>{editing?'Modificar muestreo':kind==='anden'?'Muestreo de andén':'Muestreo de proceso'}</Text>
    <Text style={styles.subtitle}>Frambuesa · captura segura sin conexión</Text>
      <Text style={styles.section}>Paso {step} de 3 · {step===1?'Datos generales':step===2?'Formato de muestreo':'Resultado final'}</Text>
      {step===1&&<><Choice label="Rancho" options={catalogOptions.ranchos} value={rancho} onChange={setRancho}/>
      {kind==='anden'&&<><Input label="Sector" value={sector} onChange={setSector}/><Input label="Licencia" value={licencia} onChange={setLicencia}/><Input label="Grados Brix" value={brix} onChange={setBrix} keyboard="numeric"/><Choice label="Variedad" options={catalogOptions.variedades} value={variedad} onChange={setVariedad}/><Choice label="Presentación" options={presentaciones.map(p=>p.name)} value={presentacion} onChange={setPresentacion}/><Input label="Cuadrilla" value={cuadrilla} onChange={setCuadrilla}/><Input label="Embaladora" value={embaladora} onChange={setEmbaladora}/><Input label="Peso en gramos" value={peso} onChange={setPeso} keyboard="numeric"/><Input label="Frutos con larva" value={larvas} onChange={setLarvas} keyboard="numeric"/></>}
      {kind==='proceso'?<><View style={{padding:12,backgroundColor:'#FFF4DD',borderRadius:10,marginBottom:12}}><Text style={{fontWeight:'800',color:C.ink,marginBottom:8}}>Indicador de porcentaje de proceso</Text><View style={{gap:7}}><Text style={{fontSize:12,color:'#16803C',fontWeight:'800'}}>● VERDE · ÓPTIMO · hasta 5%</Text><Text style={{fontSize:12,color:'#BD8A30',fontWeight:'800'}}>● AMARILLO · PRECAUCIÓN · más de 5% y menos de 10%</Text><Text style={{fontSize:12,color:C.danger,fontWeight:'800'}}>● ROJO · ALTO · 10% o más</Text></View></View><Button title="Siguiente · Formato de muestreo" onPress={()=>setStep(2)}/></>:<><Input label="Cajas" value={cajas} onChange={setCajas} keyboard="numeric"/><Input label="Frutos inspeccionados" value={frutos} onChange={setFrutos} keyboard="numeric"/>{kind==='anden'&&<Text style={styles.notice}>Canastos sugeridos: {canastosPorCajas(n(cajas))} (1 por cada 24 cajas o fracción)</Text>}<Button title="Siguiente · Formato de muestreo" onPress={()=>{if(!Number.isInteger(n(frutos))||n(frutos)<=0||n(cajas)<0||n(taras)<0){Alert.alert('Revisar datos','Comprueba las cantidades');return;}setStep(2);}}/></>}</>}
      {step===2&&<>{kind==='proceso'&&<><Choice label="Presentación" options={presentaciones.map(p=>p.name)} value={presentacion} onChange={setPresentacion} compact/><Input label="Cuadrilla" value={cuadrilla} onChange={setCuadrilla} compact/><Input label="Embaladora" value={embaladora} onChange={setEmbaladora} compact/><Input label="Peso en gramos" value={peso} onChange={setPeso} keyboard="numeric" compact/><Input label="Frutos con larvas" value={larvas} onChange={setLarvas} keyboard="numeric" compact/><Input label="Cajas" value={cajas} onChange={setCajas} keyboard="numeric" compact/><Input label="Taras" value={taras} onChange={setTaras} keyboard="numeric" compact/><Input label="Frutos inspeccionados" value={frutos} onChange={setFrutos} keyboard="numeric" compact/><View style={{padding:10,backgroundColor:'#FFF4DD',borderRadius:10,marginBottom:10}}><Text style={{fontWeight:'700',color:processColor(liveProcess)}}>Porcentaje de proceso: {liveProcess===null?'—':liveProcess.toFixed(1)+'%'} · {processLabel(liveProcess)}</Text></View><Input label="Porcentaje empacable (%) · captura obligatoria" value={empacable} onChange={setEmpacable} keyboard="numeric" compact/></>}<Text style={styles.label}>Frutos: {frutos} · Embaladora: {embaladora||'—'}</Text><Text style={styles.section}>Defectos encontrados</Text>
      {defects.map(d=><View key={d.key} style={styles.defectRow}>
          <View style={{flex:1}}><Text style={styles.defectTitle}>{d.label}</Text><Text style={styles.defectCategory}>{d.category}</Text></View>
          <Pressable accessibilityLabel={'Restar '+d.label} onPress={()=>setCounts(prev=>({...prev,[d.key]:String(Math.max(0,n(prev[d.key]||'0')-1))}))} style={styles.counterButton}><Text style={styles.counterText}>−</Text></Pressable>
          <Text style={styles.counterValue}>{counts[d.key]||'0'}</Text>
          <Pressable accessibilityLabel={'Sumar '+d.label} onPress={()=>setCounts(prev=>({...prev,[d.key]:String(n(prev[d.key]||'0')+1)}))} style={styles.counterButton}><Text style={styles.counterText}>+</Text></Pressable>
        </View>)}
      {kind==='anden'&&<><Input label="Observaciones" value={nota} onChange={setNota}/><Text style={styles.section}>Evidencia fotográfica</Text><Button title="Tomar fotografía" onPress={async()=>{try{const permission=await ImagePicker.requestCameraPermissionsAsync();if(!permission.granted)throw new Error('Autoriza el acceso a la cámara para adjuntar evidencia.');const shot=await ImagePicker.launchCameraAsync({quality:0.75,allowsEditing:false});if(shot.canceled||!shot.assets?.[0]?.uri)return;const folder=(FileSystem.documentDirectory||'')+'evidencias/';await FileSystem.makeDirectoryAsync(folder,{intermediates:true});const target=folder+Crypto.randomUUID()+'.jpg';await FileSystem.copyAsync({from:shot.assets[0].uri,to:target});setPhotos(prev=>[...prev,target]);}catch(e){Alert.alert('Fotografía',errorMessage(e));}}}/><Text style={styles.notice}>{photos.length+storedPhotoPaths.length} fotografía(s) adjunta(s). Se guardan localmente y se suben al recuperar conexión.</Text>{photos.map((uri,index)=><View key={uri} style={{flexDirection:'row',alignItems:'center',gap:10,marginBottom:8}}><Image source={{uri}} style={{width:64,height:64,borderRadius:8}}/><Text style={{flex:1}}>Evidencia {index+1}</Text><Button title="Quitar" onPress={()=>setPhotos(prev=>prev.filter(x=>x!==uri))}/></View>)}</>}
       <Button title="Volver a datos" onPress={()=>setStep(1)}/><Button title="Siguiente · Resultado" onPress={()=>{if(!validPreview){Alert.alert('Revisar captura','Los defectos no pueden superar los frutos');return;}if(kind==='proceso'&&(!empacable.trim()||!Number.isFinite(n(empacable))||n(empacable)<0||n(empacable)>100)){Alert.alert('Dato obligatorio','Captura el porcentaje empacable entre 0 y 100 antes de continuar.');return;}setStep(3);}}/></>}
       {step===3&&<><Button title="Revisar defectos" onPress={()=>setStep(2)}/><View style={styles.capturePreviewSheet}>
         <Text style={styles.capturePreviewTitle}>{kind==='anden'?'MUESTREO DE ANDÉN':'MUESTREO DE PROCESO'}</Text>
         <Text style={styles.label}>Rancho: {rancho} · Frutos: {frutos} {kind==='anden'?'· Embaladora: '+(embaladora||'—')+' · Licencia: '+(licencia||'—')+' · Brix: '+(brix||'—'):''}</Text>
         {!validPreview&&<Text style={{color:C.danger}}>Revisa el total de frutos y defectos antes de guardar.</Text>}
         {andenPreview&&<><View style={{padding:12,borderRadius:10,backgroundColor:andenPreview.disposicion==='RECHAZO'?'#FCE4E4':andenPreview.disposicion==='REEMPAQUE'?'#FFF3D6':'#E5F3E8',marginVertical:6}}><Text style={{fontSize:17,fontWeight:'900',color:andenPreview.disposicion==='RECHAZO'?C.danger:andenPreview.disposicion==='REEMPAQUE'?'#A66B00':'#16803C'}}>RESULTADO: {andenPreview.disposicion}</Text><Text style={{fontWeight:'700',color:andenPreview.disposicion==='RECHAZO'?C.danger:C.ink}}>{andenPreview.puntos_total} puntos</Text></View><Text style={styles.label}>Condición: {(andenPreview.pct_condicion*100).toFixed(1)}% · Apariencia: {(andenPreview.pct_apariencia*100).toFixed(1)}%</Text></>}
         {procesoPreview&&<><Text style={styles.label}>Presentación: {presentacion} · Cuadrilla: {cuadrilla||'—'} · Embaladora: {embaladora||'—'}</Text><Text style={styles.label}>Peso: {peso||'—'} g · Larvas: {larvas} · Cajas: {cajas} · Taras: {taras} · Frutos: {frutos}</Text><Text style={[styles.label,{color:processColor(procesoPreview.pct_proceso)}]}>Porcentaje de proceso: {procesoPreview.pct_proceso?.toFixed(1)??'—'}% · {processLabel(procesoPreview.pct_proceso)}</Text><Text style={styles.label}>Empacable (manual): {empacable||'Pendiente'}%</Text><Text style={styles.section}>Áreas de enfoque</Text>
           <Text>Agronomía: {procesoPreview.area_agronomia.toFixed(1)}% · Cosecha: {procesoPreview.area_cosecha.toFixed(1)}%</Text>
           <Text>Actividades: {procesoPreview.area_actividades.toFixed(1)}% · Inocuidad: {procesoPreview.area_inocuidad.toFixed(1)}%</Text><Text>Poscosecha: {procesoPreview.area_poscosecha.toFixed(1)}% · Total defectos: {procesoPreview.total_defectos.toFixed(1)}%</Text></>}
         <View style={styles.capturePreviewColumns}><Text style={styles.capturePreviewColumnTitle}>DEFECTOS · CANTIDAD · %</Text></View>
         <View style={styles.capturePreviewGrid}>{activeDefects.map(d=><View key={d.key} style={[styles.capturePreviewItem,{paddingVertical:4}]}><Text style={[styles.capturePreviewDefect,{fontSize:11}]}>{d.label}</Text><Text style={styles.capturePreviewCount}>{counts[d.key]}</Text><Text style={styles.capturePreviewPercent}>{(n(counts[d.key]||'0')/totalPreview*100).toFixed(1)}%</Text></View>)}</View>
         <View style={styles.capturePreviewFooter}><Text style={styles.capturePreviewFooterText}>FRUTOS CONTADOS</Text><Text style={styles.capturePreviewFooterText}>{countedPreview} / {totalPreview}</Text></View>
       </View></>}
    {step===3&&kind==='anden'&&!editing&&<Choice label="Después de guardar" options={['Volver al inicio','Otro andén con los mismos datos']} value={continueAnden?'Otro andén con los mismos datos':'Volver al inicio'} onChange={v=>setContinueAnden(v.startsWith('Otro'))}/>}
      {step===3&&<><Button title="Ver resumen compacto para captura" onPress={()=>setSharePreview(true)}/>
    <Modal visible={sharePreview} animationType="slide" onRequestClose={()=>setSharePreview(false)}>
      <View style={styles.capturePreviewPage}>
        <View style={styles.capturePreviewTop}><Text style={styles.capturePreviewBrand}>QUALYX · {kind==='anden'?'ANDENES':'FRUTA PROCESO'}</Text><Pressable onPress={()=>setSharePreview(false)} accessibilityLabel="Cerrar resumen"><Text style={styles.capturePreviewClose}>✕</Text></Pressable></View>
        <View style={styles.capturePreviewSheet}>
          <Text style={styles.capturePreviewTitle}>RESUMEN DE MUESTREO</Text>
          <Text style={styles.capturePreviewMeta}>{new Date().toLocaleDateString('es-MX')} · {rancho}{sector?' · '+sector:''}</Text>
          <Text style={styles.capturePreviewMeta}>Frutos: {frutos} · Contados: {countedPreview} {kind==='anden'?'· Embaladora: '+(embaladora||'—'):''}</Text>
          {andenPreview&&<Text style={[styles.capturePreviewStatus,{color:andenPreview.disposicion==='RECHAZO'?C.danger:andenPreview.disposicion==='REEMPAQUE'?'#A66B00':'#17663B',backgroundColor:andenPreview.disposicion==='RECHAZO'?'#FCE4E4':andenPreview.disposicion==='REEMPAQUE'?'#FFF3D6':'#E5F3E8'}]}>{andenPreview.disposicion} · {andenPreview.puntos_total} pts · Cond. {(andenPreview.pct_condicion*100).toFixed(1)}% · Apar. {(andenPreview.pct_apariencia*100).toFixed(1)}%</Text>}
          {procesoPreview&&<><Text style={styles.capturePreviewMeta}>{presentacion} · Cuadrilla {cuadrilla||'—'} · Embaladora {embaladora||'—'} · Peso {peso||'—'} g · Larvas {larvas} · Cajas {cajas} · Taras {taras}</Text><Text style={[styles.capturePreviewStatus,{color:processColor(procesoPreview.pct_proceso),backgroundColor:processColor(procesoPreview.pct_proceso)==='#16803C'?'#E5F3E8':processColor(procesoPreview.pct_proceso)==='#BD8A30'?'#FFF3D6':'#FCE4E4'}]}>Proceso {(procesoPreview.pct_proceso?.toFixed(1)??'—')}% · Empacable {empacable||'—'}%</Text><Text style={styles.capturePreviewMeta}>Agronomía {procesoPreview.area_agronomia.toFixed(1)}% · Cosecha {procesoPreview.area_cosecha.toFixed(1)}%</Text><Text style={styles.capturePreviewMeta}>Actividades {procesoPreview.area_actividades.toFixed(1)}% · Inocuidad {procesoPreview.area_inocuidad.toFixed(1)}% · Poscosecha {procesoPreview.area_poscosecha.toFixed(1)}% · Total defectos {procesoPreview.total_defectos.toFixed(1)}%</Text></>}
          <View style={styles.capturePreviewColumns}><Text style={styles.capturePreviewColumnTitle}>DEFECTO</Text><Text style={styles.capturePreviewColumnTitle}>CANT.</Text><Text style={styles.capturePreviewColumnTitle}>%</Text></View>
          <View style={styles.capturePreviewGrid}>
            {activeDefects.map(d=><View key={d.key} style={[styles.capturePreviewItem,{paddingVertical:activeDefects.length>14?3:activeDefects.length>8?6:10}]}>
              <Text style={[styles.capturePreviewDefect,{fontSize:activeDefects.length>14?10:activeDefects.length>8?12:14}]}>{d.label}</Text>
              <Text style={styles.capturePreviewCount}>{counts[d.key]}</Text>
              <Text style={styles.capturePreviewPercent}>{totalPreview>0?(n(counts[d.key]||'0')/totalPreview*100).toFixed(1):'—'}%</Text>
            </View>)}
          </View>
          {activeDefects.length===0&&<Text style={styles.capturePreviewEmpty}>Sin defectos registrados</Text>}
          <View style={styles.capturePreviewFooter}><Text style={styles.capturePreviewFooterText}>TOTAL {countedPreview} / {totalPreview}</Text><Text style={styles.capturePreviewFooterText}>{totalPreview>0?(countedPreview/totalPreview*100).toFixed(1):'—'}%</Text></View>
          {!validPreview&&<Text style={{color:C.danger,fontSize:11}}>Revisar cantidades antes de guardar.</Text>}
        </View>
        <Text style={styles.capturePreviewHint}>Vista compacta para captura de pantalla. Si el contenido supera la altura del teléfono, usa una captura con desplazamiento.</Text>
      </View>
    </Modal></>}
    {step===3&&<Button title={saving?'Guardando…':editing?'Revisar modificaciones':'Revisar y confirmar muestreo'} disabled={saving} onPress={()=>{
      const total=n(frutos);
      const counted=defects.reduce((s,d)=>s+n(counts[d.key]||'0'),0);
      const score=kind==='anden'&&total>0?scoreAnden(Object.fromEntries(defects.map(d=>[d.key,n(counts[d.key]||'0')])),total,n(larvas)):null;
      const summary=['Rancho: '+rancho,'Sector: '+(sector||'—'),'Variedad: '+variedad+' · '+presentacion,'Cuadrilla: '+(cuadrilla||'—'),'Evaluador: '+profile.display_name,'Frutos inspeccionados: '+total,'Defectos contados: '+counted,kind==='anden'?'Embaladora: '+(embaladora||'Sin especificar'):'Taras: '+taras+' (3 kg c/u)',kind==='anden'?'Resultado: '+(score?.disposicion||'Pendiente'):'Empacable manual: '+(empacable||'Sin capturar')+'%'].join('\n');
      Alert.alert('Confirmar muestreo',summary+'\n\n¿Confirmas guardar este registro?',[
        {text:'Revisar',style:'cancel'},
        {text:editing?'Guardar cambios':'Confirmar y guardar',onPress:()=>{void save();}}
      ]);
    }}/>}
  </>;
}
const styles=StyleSheet.create({
  capturePreviewPage:{flex:1,backgroundColor:'#FAF7F1',paddingHorizontal:12,paddingTop:34,paddingBottom:14,justifyContent:'center'},
  capturePreviewTop:{flexDirection:'row',justifyContent:'space-between',alignItems:'center',marginBottom:8},capturePreviewBrand:{fontSize:14,fontWeight:'800',color:'#6A2433'},capturePreviewClose:{fontSize:23,color:'#6A2433',paddingHorizontal:12},
  capturePreviewSheet:{backgroundColor:'#FFFFFF',borderRadius:12,borderWidth:1,borderColor:'#E3DDD6',overflow:'hidden',paddingBottom:8},
  capturePreviewTitle:{backgroundColor:'#F8DFE8',textAlign:'center',color:'#BE3562',fontWeight:'800',fontSize:16,padding:10},
  capturePreviewMeta:{fontSize:11,color:'#454B48',paddingHorizontal:10,paddingTop:6},
  capturePreviewStatus:{fontSize:12,fontWeight:'800',color:'#17663B',backgroundColor:'#E5F3E8',padding:9,marginTop:7},
  capturePreviewColumns:{flexDirection:'row',justifyContent:'space-between',backgroundColor:'#EAE6E0',padding:8},
  capturePreviewColumnTitle:{fontSize:10,fontWeight:'800',color:'#444'},
  capturePreviewGrid:{flexDirection:'row',flexWrap:'wrap',paddingHorizontal:5,paddingTop:4},
  capturePreviewItem:{width:'50%',flexDirection:'row',alignItems:'center',borderBottomWidth:1,borderBottomColor:'#EEEAE5',paddingHorizontal:5,gap:3},
  capturePreviewDefect:{flex:1,color:'#222',fontWeight:'600'},
  capturePreviewCount:{minWidth:18,textAlign:'right',fontSize:12,fontWeight:'800',color:'#222'},
  capturePreviewPercent:{minWidth:35,textAlign:'right',fontSize:11,color:'#4D5752'},
  capturePreviewEmpty:{textAlign:'center',padding:20,color:'#777'},
  capturePreviewFooter:{backgroundColor:'#E4F2E6',padding:10,flexDirection:'row',justifyContent:'space-between'},
  capturePreviewFooterText:{fontSize:13,fontWeight:'800',color:'#17663B'},
  capturePreviewHint:{fontSize:11,textAlign:'center',color:'#686868',marginTop:10},
  dropdownHeader:{flexDirection:'row',alignItems:'center',justifyContent:'space-between',backgroundColor:C.white,borderWidth:1,borderColor:C.line,borderRadius:14,paddingVertical:16,paddingHorizontal:17},
  dropdownValue:{fontSize:16,color:C.ink,fontStyle:'italic',flex:1},
  dropdownArrow:{fontSize:24,color:C.burgundy,marginLeft:12},
  dropdownOptions:{backgroundColor:C.white,borderWidth:1,borderColor:C.line,borderRadius:14,marginTop:5,overflow:'hidden'},
  dropdownOption:{flexDirection:'row',justifyContent:'space-between',alignItems:'center',paddingVertical:13,paddingHorizontal:17,borderBottomWidth:StyleSheet.hairlineWidth,borderBottomColor:C.line},
  dropdownOptionSelected:{backgroundColor:'#FFF2DE'},
  dropdownOptionText:{fontSize:15,color:C.ink,flex:1},
  moduleTile:{flexDirection:'row',alignItems:'center',backgroundColor:C.white,borderWidth:1,borderColor:C.line,borderRadius:17,padding:17,marginBottom:12,gap:14},
  moduleIcon:{fontSize:27,width:40,textAlign:'center'},moduleTitle:{fontSize:19,fontWeight:'700',color:C.ink},moduleDescription:{fontSize:12,color:C.muted,marginTop:4,lineHeight:18},moduleArrow:{fontSize:28,color:C.gold},
  defectRow:{flexDirection:'row',alignItems:'center',backgroundColor:'#FFFFFF',borderWidth:1,borderColor:'#DDDCD6',borderRadius:14,paddingVertical:11,paddingHorizontal:10,marginBottom:7,gap:6},
  defectTitle:{fontSize:15,fontWeight:'600',color:C.ink},defectCategory:{fontSize:11,color:C.muted,marginTop:3},
  counterButton:{width:32,height:34,alignItems:'center',justifyContent:'center',borderRadius:9,backgroundColor:'#F5F7F2'},
  counterText:{fontSize:24,color:'#145D3B',fontWeight:'600'},counterValue:{minWidth:24,textAlign:'center',fontSize:16,fontWeight:'800',color:C.ink},
  page:{flex:1,backgroundColor:C.cream},body:{padding:20,paddingBottom:60},
  top:{backgroundColor:C.burgundy,paddingHorizontal:20,paddingTop:58,paddingBottom:20},
  topTitle:{fontStyle:'italic',fontFamily:'serif',fontSize:23,fontWeight:'800',color:C.white},topSmall:{color:'#FBE9CE',marginTop:5},
  center:{flex:1,alignItems:'center',justifyContent:'center'},
  auth:{flexGrow:1,justifyContent:'center',padding:24,backgroundColor:C.cream},
  entryPage:{flexGrow:1,justifyContent:'space-between',paddingHorizontal:28,paddingTop:60,paddingBottom:30,backgroundColor:'#FFF9F3'},
  entryCenter:{flex:1,justifyContent:'center',alignItems:'center',width:'100%',maxWidth:460,alignSelf:'center'},
  entryFruitLogo:{height:220,width:280,marginBottom:16,alignSelf:'center'},
  entryCherryText:{fontSize:52},
  entryBrand:{fontSize:43,fontStyle:'italic',fontFamily:'serif',fontWeight:'700',color:'#A52A35',textAlign:'center',letterSpacing:-1},
  entryBrandPro:{fontSize:17,fontStyle:'italic',fontFamily:'serif',color:'#BD8A30',marginTop:-6,textAlign:'center'},
  entryRule:{width:65,height:2,backgroundColor:'#BD8A30',marginTop:23,marginBottom:34},
  entryPrimary:{backgroundColor:C.burgundy,paddingVertical:19,borderRadius:17,width:'100%',alignItems:'center',marginBottom:14},
  entryPrimaryText:{fontStyle:'italic',fontFamily:'serif',color:'#FFFFFF',fontSize:17,fontWeight:'800'},
  entrySecondary:{backgroundColor:'#FFFFFF',borderColor:'#E8CBA3',borderWidth:1.5,paddingVertical:19,borderRadius:17,width:'100%',alignItems:'center'},
  entrySecondaryText:{fontStyle:'italic',fontFamily:'serif',color:'#A52A35',fontSize:17,fontWeight:'800'},
  entryBack:{alignSelf:'flex-start',paddingVertical:10,marginBottom:8},
  entryBackText:{fontStyle:'italic',fontFamily:'serif',color:'#A52A35',fontWeight:'700',fontSize:14},
  entryLoginCard:{width:'100%',backgroundColor:'#FFFFFF',borderRadius:22,padding:20,borderWidth:1,borderColor:'#E8CBA3'},
  entryLoginTitle:{fontStyle:'italic',fontFamily:'serif',fontSize:21,fontWeight:'800',color:'#651B2B',marginBottom:5},
  entryLoginHint:{fontSize:13,color:'#80636A',marginBottom:20,lineHeight:19},
  entryRegister:{alignItems:'center',padding:10},
  entryRegisterText:{color:'#A52A35',fontWeight:'700',fontSize:13},
  entryFooter:{textAlign:'center',fontSize:10,letterSpacing:1.3,color:'#80636A',fontWeight:'700',marginTop:20},
  authModern:{flexGrow:1,backgroundColor:'#FFF9F3'},
  authHero:{minHeight:320,backgroundColor:C.burgundy,paddingHorizontal:26,paddingTop:62,paddingBottom:30,overflow:'hidden',position:'relative'},
  authOrbLarge:{position:'absolute',width:300,height:300,borderRadius:150,backgroundColor:'#842537',right:-130,top:-80},
  authOrbSmall:{position:'absolute',width:185,height:185,borderRadius:100,backgroundColor:'#A52A35',right:-70,bottom:-120},
  authTopline:{flexDirection:'row',alignItems:'center',gap:10},
  authBrandMark:{width:42,height:42,borderRadius:13,backgroundColor:'#F6DEAF',alignItems:'center',justifyContent:'center'},
  authBrandMarkText:{color:'#651B2B',fontWeight:'900',fontSize:16},
  authEdition:{color:'#FBE9CE',fontSize:11,fontWeight:'800',letterSpacing:2},
  authHeroContent:{marginTop:30},
  authEyebrow:{color:'#F6DEAF',fontSize:10,fontWeight:'800',letterSpacing:1.6,marginBottom:12},
  authHeroTitle:{fontStyle:'italic',fontFamily:'serif',color:'#FFFFFF',fontSize:31,fontWeight:'900',lineHeight:37,letterSpacing:-.7},
  authHeroDesc:{color:'#FBE9CE',fontSize:13,lineHeight:20,marginTop:12,maxWidth:310},
  authHeroTags:{flexDirection:'row',flexWrap:'wrap',gap:7,marginTop:20},
  authHeroTag:{color:'#FBE9CE',backgroundColor:'#FFFFFF20',borderColor:'#FFFFFF30',borderWidth:1,overflow:'hidden',borderRadius:20,paddingHorizontal:10,paddingVertical:6,fontSize:11,fontWeight:'600'},
  authContent:{paddingHorizontal:23,paddingTop:26,paddingBottom:36},
  authWelcome:{fontStyle:'italic',fontFamily:'serif',fontSize:24,fontWeight:'900',color:'#651B2B',letterSpacing:-.5},
  authLead:{fontSize:13,color:'#80636A',marginTop:7,marginBottom:22,lineHeight:20},
  authForm:{backgroundColor:'#FFFFFF',borderRadius:22,padding:19,borderWidth:1,borderColor:'#E8CBA3',marginBottom:18},
  authFooter:{textAlign:'center',color:'#80636A',fontSize:10,fontWeight:'700',letterSpacing:1.2,marginBottom:14},
  brand:{fontStyle:'italic',fontFamily:'serif',fontSize:30,fontWeight:'900',color:C.green,marginBottom:6},
  heading:{fontStyle:'italic',fontFamily:'serif',fontSize:23,fontWeight:'800',color:C.ink,marginBottom:8},
  subtitle:{fontSize:14,color:C.muted,marginBottom:20},
  section:{fontStyle:'italic',fontFamily:'serif',fontSize:18,fontWeight:'800',color:C.ink,marginVertical:14},
  label:{fontStyle:'italic',fontFamily:'serif',fontSize:14,fontWeight:'700',color:C.ink,marginBottom:7},
  card:{backgroundColor:C.white,borderLeftWidth:4,borderLeftColor:C.gold,borderRadius:16,padding:16,marginBottom:14,borderWidth:1,borderColor:C.line},
  button:{backgroundColor:C.green,borderWidth:1,borderColor:C.gold,borderRadius:12,padding:15,alignItems:'center',marginBottom:12},
  buttonText:{fontStyle:'italic',fontFamily:'serif',fontSize:15,fontWeight:'800',color:C.white},
  big:{fontStyle:'italic',fontFamily:'serif',fontSize:30,fontWeight:'900',color:C.green,marginVertical:6},
  choices:{flexDirection:'row',flexWrap:'wrap',gap:7},
  chip:{paddingHorizontal:11,paddingVertical:10,borderWidth:1,borderColor:C.line,borderRadius:10,backgroundColor:C.white},
  selected:{backgroundColor:C.burgundy,borderColor:C.gold},
  notice:{padding:12,backgroundColor:'#FFF0DC',borderRadius:10,marginBottom:16,color:C.ink},
  logout:{color:C.danger,textAlign:'center',fontWeight:'700',padding:16},
  back:{fontStyle:'italic',fontFamily:'serif',color:C.green,fontWeight:'700',marginBottom:20},
});
