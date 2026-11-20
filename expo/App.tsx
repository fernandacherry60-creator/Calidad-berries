import React, { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Alert, AppState, Image, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import * as Linking from 'expo-linking';
import * as Crypto from 'expo-crypto';
import NetInfo from '@react-native-community/netinfo';
import { supabase, loadProfile, redeemPendingInvitation, type Profile } from './src/lib/cloud';
import { savePending, saveSample, updatePendingSample, updateSyncedSample, syncSamples, localSamples, pendingCount, cacheVerifiedProfile, getCachedProfile, clearCachedProfile, type TableName, type LocalSample } from './src/lib/offline';
import { andenDefects, procesoDefects, scoreAnden, scoreProceso, ranchos, variedades, presentaciones, puestos, canastosPorCajas } from './src/lib/rules';

type Screen = 'home'|'team'|'history'|'anden'|'proceso'|'semaforo'|'cultivos'|'calculadora'|'pesos'|'ayuda'|'informes';
const C = { ink:'#502027', green:'#A52A35', cream:'#FFF9F3', muted:'#80636A', line:'#E8CBA3', white:'#FFFFFF', danger:'#B71C32', gold:'#BD8A30', burgundy:'#651B2B' };
const fieldStyle = { borderWidth:1,borderColor:C.line,borderRadius:12,padding:12,backgroundColor:C.white,fontSize:15,color:C.ink,fontStyle:'italic' } as const;
const Button = ({title,onPress,disabled=false}: {title:string;onPress:()=>void;disabled?:boolean}) =>
  <Pressable disabled={disabled} onPress={onPress} style={[styles.button,disabled&&{opacity:.5}]}><Text style={styles.buttonText}>{title}</Text></Pressable>;
const Input = ({label,value,onChange,secure=false,keyboard='default'}: {label:string;value:string;onChange:(v:string)=>void;secure?:boolean;keyboard?:'default'|'numeric'|'email-address'}) =>
  <View style={{marginBottom:12}}><Text style={styles.label}>{label}</Text><TextInput autoCapitalize={keyboard==='email-address'?'none':'sentences'} secureTextEntry={secure} keyboardType={keyboard} style={fieldStyle} value={value} onChangeText={onChange}/></View>;
const ModuleTile = ({icon,title,description,onPress}:{icon:string;title:string;description:string;onPress:()=>void}) =>
  <Pressable accessibilityRole="button" onPress={onPress} style={styles.moduleTile}><Text style={styles.moduleIcon}>{icon}</Text><View style={{flex:1}}><Text style={styles.moduleTitle}>{title}</Text><Text style={styles.moduleDescription}>{description}</Text></View><Text style={styles.moduleArrow}>›</Text></Pressable>;
const Choice = ({label,options,value,onChange}: {label:string;options:string[];value:string;onChange:(v:string)=>void}) => {
  const [expanded,setExpanded]=useState(false);
  return <View style={{marginBottom:12}}>
    <Text style={styles.label}>{label}</Text>
    <Pressable accessibilityRole="button" accessibilityLabel={label+': '+value} accessibilityState={{expanded}} onPress={()=>setExpanded(open=>!open)} style={styles.dropdownHeader}>
      <Text style={styles.dropdownValue}>{value||'Seleccionar'}</Text><Text style={styles.dropdownArrow}>{expanded?'▴':'▾'}</Text>
    </Pressable>
    {expanded&&<View style={styles.dropdownOptions}>{options.map(v=><Pressable key={v} accessibilityRole="button" accessibilityState={{selected:value===v}} onPress={()=>{onChange(v);setExpanded(false);}} style={[styles.dropdownOption,value===v&&styles.dropdownOptionSelected]}><Text style={[styles.dropdownOptionText,value===v&&{color:C.burgundy,fontWeight:'700'}]}>{v}</Text>{value===v&&<Text style={{color:C.gold}}>✓</Text>}</Pressable>)}</View>}
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

export default function App() {
  const [profile,setProfile]=useState<Profile|null>(null);
  const [userId,setUserId]=useState<string|null>(null);
  const [busy,setBusy]=useState(true);
  const [recovering,setRecovering]=useState(false);
  const [screen,setScreen]=useState<Screen>('cultivos');
  const [editing,setEditing]=useState<LocalSample|null>(null);
  const [panel,setPanel]=useState<'admin'|'worker'>('admin');
  const [pending,setPending]=useState(0);
  const [features,setFeatures]=useState<Record<string,boolean>>({enable_sampling:true,enable_semaforo:true,enable_cloud_sync:true});
  const refresh=useCallback(async()=>{
    const {data:{session}}=await supabase.auth.getSession();
    const user=session?.user;
    if(!user){setUserId(null);setProfile(null);return;}
    // Comprobar que la sesión guardada sigue perteneciendo a un usuario real.
    const {data:validated,error:authError}=await supabase.auth.getUser();
    if(authError||!validated.user||validated.user.id!==user.id){
      await supabase.auth.signOut({scope:'local'});
      setUserId(null);setProfile(null);return;
    }
    setUserId(validated.user.id);
    let p:Profile|null=null;
    try {
      p=await loadProfile(user.id);
      if(!p&&user.email){await redeemPendingInvitation(user.email);p=await loadProfile(user.id);}
      if(p?.active)await cacheVerifiedProfile(p);
      else await clearCachedProfile();
    } catch(e) {
      // Sin internet: solo se acepta un perfil que antes fue validado por el servidor.
      p=await getCachedProfile(user.id);
    }
    setProfile(p?.active?p:null);
    if(p?.active)setPending(await pendingCount(p.user_id));
  },[]);
  useEffect(()=>{
    let alive=true;
    (async()=>{try{
      const initial=await Linking.getInitialURL();if(initial)setRecovering(await handleAuthLink(initial));
      await refresh();
    }catch(e){Alert.alert('Inicio',errorMessage(e));}finally{if(alive)setBusy(false);}})();
    const link=Linking.addEventListener('url',({url})=>{handleAuthLink(url).then(async recovery=>{if(recovery)setRecovering(true);await refresh();}).catch(e=>Alert.alert('Enlace',errorMessage(e)));});
    const auth=supabase.auth.onAuthStateChange(()=>{setTimeout(()=>{refresh().catch(()=>{});},0);});
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
  const navigate=(next:Screen)=>{if(next==='anden'||next==='proceso'||next==='semaforo')setEditing(null);setScreen(next);};
  const openEdit=(row:LocalSample)=>{setEditing(row);setScreen(row.table_name==='muestreos_anden'?'anden':'proceso');};
  const dualPanel=profile.role==='admin'&&profile.email.toLowerCase()==='yamilethklunder@gmail.com';
  const adminPanel=profile.role==='admin'&&(!dualPanel||panel==='admin');
  return <View style={styles.page}>
    <View style={styles.top}><Text style={styles.topTitle}>QUALYX</Text><Text style={styles.topSmall}>{profile.display_name} · {adminPanel?'Administradora':'Trabajadora'}</Text></View>
    <ScrollView contentContainerStyle={styles.body}>
      {screen!=='home'&&<Pressable onPress={()=>navigate('home')}><Text style={styles.back}>‹ Volver al inicio</Text></Pressable>}
      {screen==='cultivos'&&<><Text style={styles.heading}>QUALYX · Cultivos</Text><Text style={styles.subtitle}>Selecciona el cultivo a muestrear</Text><Button title="🍓 Frambuesa · disponible" onPress={()=>navigate('home')}/></>}
      {screen==='home'&&<>
        {dualPanel&&<Choice label="Panel de trabajo" options={['Administradora','Trabajadora']} value={panel==='admin'?'Administradora':'Trabajadora'} onChange={v=>setPanel(v==='Administradora'?'admin':'worker')}/>}
        <Text style={styles.heading}>Módulos · Frambuesa</Text>
        <Text style={styles.subtitle}>Captura offline y sincronización segura con Supabase</Text>
        <View style={styles.card}><Text style={styles.label}>Registros pendientes en este teléfono</Text><Text style={styles.big}>{pending}</Text>
          <Button title="Sincronizar ahora" onPress={async()=>{try{const r=await syncSamples(profile);setPending(r.pending);Alert.alert('Sincronización',`Subidos: ${r.uploaded}. Pendientes: ${r.pending}`);}catch(e){Alert.alert('Sin conexión',errorMessage(e));}}}/></View>
        {features.enable_sampling!==false&&<><ModuleTile icon="🚚" title="Andenes" description="Recepción, condición, apariencia y disposición" onPress={()=>navigate('anden')}/><ModuleTile icon="⚗️" title="Fruta proceso" description="Defectos, áreas de enfoque y porcentaje de proceso" onPress={()=>navigate('proceso')}/></>}
        {features.enable_semaforo!==false&&<ModuleTile icon="🚦" title="Semáforo" description="Registrar nivel de calidad" onPress={()=>navigate('semaforo')}/>}
        <ModuleTile icon="🧮" title="Calculadora de defectos" description="Porcentajes de la muestra sin guardar" onPress={()=>navigate('calculadora')}/>
        <ModuleTile icon="⚖️" title="Pesos de clamshells" description="Verificar rangos por presentación" onPress={()=>navigate('pesos')}/>
        <ModuleTile icon="📖" title="Ayuda visual" description="Criterios de calidad y defectos" onPress={()=>navigate('ayuda')}/>
        <ModuleTile icon="📊" title="Informes de calidad" description="Reportes, estadísticas y gráficas de muestreos" onPress={()=>navigate('informes')}/>
        <ModuleTile icon="🕘" title="Historial de este teléfono" description="Consultar y editar muestreos guardados" onPress={()=>navigate('history')}/>
        {adminPanel&&<ModuleTile icon="☁️" title="Trabajadores y muestreos en la nube" description="Administrar personal y registros sincronizados" onPress={()=>navigate('team')}/>}
        <Pressable onPress={logout}><Text style={styles.logout}>Cerrar sesión</Text></Pressable>
      </>}
      {screen==='team'&&adminPanel&&<TeamView onEdit={openEdit}/>}
      {screen==='calculadora'&&<CalculatorView/>}
      {screen==='pesos'&&<WeightsView/>}
      {screen==='ayuda'&&<HelpView/>}
      {screen==='informes'&&<ReportsView/>}
      {screen==='history'&&<HistoryView profile={profile} onEdit={openEdit}/>}
      {(screen==='anden'||screen==='proceso'||screen==='semaforo')&&<CaptureView kind={screen} profile={profile} editing={editing} onSaved={async()=>{setEditing(null);setPending(await pendingCount(profile.user_id));navigate('home');}}/>}
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
    {samples.map(m=><View key={String(m.uuid)} style={styles.card}><Text style={styles.label}>{String(m.tipo)} · {String(m.cultivo)}</Text><Text>{String(m.usuario_nombre||m.usuario_email||'Sin nombre')}</Text><Text>{String(m.fecha)}</Text>{m.tipo!=='semaforo'&&<Button title="Modificar este muestreo" onPress={()=>onEdit({uuid:String(m.uuid),owner_id:String(m.owner_id),table_name:m.tipo as TableName,payload:JSON.stringify(m),fecha:String(m.fecha),synced:1})}/>}</View>)}
  </>;
}
function CalculatorView(){
  const [total,setTotal]=useState('100');
  const [defects,setDefects]=useState('0');
  const sample=n(total),affected=n(defects);
  const valid=Number.isInteger(sample)&&sample>0&&Number.isInteger(affected)&&affected>=0&&affected<=sample;
  return <><Text style={styles.heading}>Calculadora de defectos</Text><Text style={styles.subtitle}>Simulación sin guardar registros</Text>
    <Input label="Frutos de la muestra" value={total} onChange={setTotal} keyboard="numeric"/>
    <Input label="Frutos con defectos" value={defects} onChange={setDefects} keyboard="numeric"/>
    <View style={styles.card}><Text style={styles.big}>{valid?(affected/sample*100).toFixed(1)+' %':'—'}</Text><Text>{valid?'Porcentaje de defectos':'Revisa los conteos'}</Text></View></>;
}
function WeightsView(){
  const [weight,setWeight]=useState('');
  const value=weight.trim()?Number(weight.replace(',','.')):NaN;
  return <><Text style={styles.heading}>Pesos de clamshells</Text><Text style={styles.subtitle}>Verificación por presentación · gramos</Text>
    <Input label="Peso medido (g)" value={weight} onChange={setWeight} keyboard="numeric"/>
    {presentaciones.map(p=><View key={p.name} style={styles.card}><Text style={styles.label}>{p.name}</Text>
      <Text>Rango: {p.min}–{p.max} g</Text><Text style={{color:Number.isFinite(value)?value>=p.min&&value<=p.max?C.green:C.danger:C.muted}}>{Number.isFinite(value)?value>=p.min&&value<=p.max?'Dentro de rango':'Fuera de rango':'Ingresa un peso'}</Text></View>)}</>;
}
function HelpView(){
  return <><Text style={styles.heading}>Ayuda visual de calidad</Text><Text style={styles.subtitle}>Criterios de referencia; consulta el protocolo de la empresa antes de determinar una disposición.</Text>
    <Text style={styles.section}>Condición y apariencia · Andenes</Text>
    {andenDefects.map(d=><View key={d.key} style={styles.card}><Text style={styles.label}>{d.label}</Text><Text>{d.category==='condicion'?'Condición':'Apariencia'}</Text>{d.key==='Excreta de pajaro'&&<Text style={{color:C.danger}}>Un fruto implica rechazo automático</Text>}</View>)}
    <Text style={styles.section}>Defectos de fruta proceso</Text>
    {procesoDefects.map(d=><View key={d.key} style={styles.card}><Text style={styles.label}>{d.label}</Text><Text>{d.category}</Text></View>)}</>;
}
function ReportsView(){
  const [period,setPeriod]=useState('Hoy');
  const [rancho,setRancho]=useState('Todos');
  const [rows,setRows]=useState<Record<string,unknown>[]>([]);
  const [loading,setLoading]=useState(false);
  const load=async()=>{
    setLoading(true);
    try{
      const days=period==='Hoy'?1:period==='7 días'?7:30;
      const from=new Date();from.setHours(0,0,0,0);from.setDate(from.getDate()-(days-1));
      const results:Record<string,unknown>[]=[];
      for(const table of ['muestreos_anden','muestreos_proceso'] as const){
        // Ambas tablas no comparten todas las columnas.
        const columns=table==='muestreos_anden'?'uuid,fecha,rancho,disposicion,pct_condicion,pct_apariencia,defectos_json':'uuid,fecha,rancho,total_defectos,potencial_empacable,defectos_json';
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
  const maxDefect=Math.max(1,...topDefects.map(x=>x[1]));
  const daily:Record<string,number>={};
  for(const r of rows){const day=String(r.fecha).slice(0,10);daily[day]=(daily[day]||0)+1;}
  const trend=Object.entries(daily).sort((a,b)=>a[0].localeCompare(b[0]));
  const maxDaily=Math.max(1,...trend.map(x=>x[1]));
  return <><Text style={styles.heading}>Informes de calidad</Text>
    <Choice label="Periodo" options={['Hoy','7 días','30 días']} value={period} onChange={setPeriod}/>
    <Choice label="Rancho" options={['Todos',...ranchos]} value={rancho} onChange={setRancho}/>
    <Button title={loading?'Consultando…':'Generar informe'} disabled={loading} onPress={()=>void load()}/>
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
    {rows.map((r,i)=><View key={String(r.uuid)+String(i)} style={styles.card}><Text>{r.tabla==='muestreos_anden'?'Andén':'Proceso'} · {String(r.rancho)}</Text><Text>{String(r.fecha).slice(0,10)} · {String(r.disposicion||('Empacable '+Number(r.potencial_empacable||0).toFixed(1)+'%'))}</Text></View>)}
  </>;
}
function HistoryView({profile,onEdit}:{profile:Profile;onEdit:(row:LocalSample)=>void}){
  const [rows,setRows]=useState<LocalSample[]>([]);
  useEffect(()=>{void localSamples(profile.user_id).then(setRows).catch(e=>Alert.alert('Historial',errorMessage(e)));},[profile.user_id]);
  return <><Text style={styles.heading}>Historial local</Text>{rows.length===0&&<Text>Sin registros en este teléfono</Text>}
    {rows.map(row=><View key={row.uuid} style={styles.card}><Text style={styles.label}>{row.table_name}</Text><Text>{row.fecha}</Text><Text style={{color:row.synced?C.green:C.danger}}>{row.synced?'Sincronizado':'Pendiente'}</Text>{row.table_name!=='semaforo'&&<Button title="Modificar muestreo" onPress={()=>onEdit(row)}/>}</View>)}</>;
}
function CaptureView({kind,profile,onSaved,editing}:{kind:'anden'|'proceso'|'semaforo';profile:Profile;onSaved:()=>Promise<void>;editing:LocalSample|null}){
  const [rancho,setRancho]=useState(ranchos[0]),[sector,setSector]=useState(''),[variedad,setVariedad]=useState(variedades[0]);
  const [presentacion,setPresentacion]=useState(presentaciones[0].name),[cuadrilla,setCuadrilla]=useState('');
  const [cajas,setCajas]=useState('0'),[taras,setTaras]=useState('0'),[frutos,setFrutos]=useState('100');
  const [larvas,setLarvas]=useState('0'),[peso,setPeso]=useState('');
  const [embaladora,setEmbaladora]=useState(''),[nota,setNota]=useState('');
  const [empacable,setEmpacable]=useState('');
  const [continueAnden,setContinueAnden]=useState(false);
  const [categoria,setCategoria]=useState('Condición'),[nivel,setNivel]=useState('ok');
  const [counts,setCounts]=useState<Record<string,string>>({});
  const [saving,setSaving]=useState(false);
  const defects=kind==='anden'?andenDefects:procesoDefects;
  const totalPreview=n(frutos);
  const previewCounts=Object.fromEntries(defects.map(d=>[d.key,n(counts[d.key]||'0')]));
  const validPreview=totalPreview>0&&Object.values(previewCounts).reduce((s,v)=>s+v,0)<=totalPreview;
  const andenPreview=kind==='anden'&&validPreview?scoreAnden(previewCounts,totalPreview,n(larvas)):null;
  const procesoPreview=kind==='proceso'&&validPreview?scoreProceso(previewCounts,totalPreview,n(cajas),n(taras),empacable.trim()?n(empacable):undefined):null;
  useEffect(()=>{
    if(!editing)return;
    const p=JSON.parse(editing.payload) as Record<string,unknown>;
    setRancho(String(p.rancho||ranchos[0]));setSector(String(p.sector||''));setVariedad(String(p.variedad||variedades[0]));
    setPresentacion(String(p.presentacion||presentaciones[0].name));setCuadrilla(String(p.cuadrilla||''));
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
      if(kind!=='semaforo'&&(!Number.isInteger(total)||total<=0||!Number.isInteger(box)||box<0))throw new Error('Revisa los totales de frutos y cajas');
      if(!nonNegative(t)||!Number.isInteger(t)||!nonNegative(larva)||!Number.isInteger(larva))throw new Error('Los conteos deben ser enteros positivos');
      const defectCounts:Record<string,number>={};
      for(const d of defects){
        const raw=counts[d.key]||'0',value=Number(raw);
        if(!Number.isInteger(value)||value<0)throw new Error('Conteo inválido: '+d.label);
        defectCounts[d.key]=value;
      }
      const uuid=Crypto.randomUUID(),fecha=new Date().toISOString();
      let payload:Record<string,unknown>;
      let table:TableName;
      if(kind==='anden'){
        if(Object.values(defectCounts).reduce((a,b)=>a+b,0)>total)throw new Error('Los defectos superan el total de frutos');
        const score=scoreAnden(defectCounts,total,larva);
        payload={uuid,fecha,cultivo:'Frambuesa',rancho,sector,variedad,presentacion,cuadrilla,
          cajas_recibidas:box,canastos:canastosPorCajas(box),fruta_muestra:total,
          peso:peso?n(peso):null,frutos_larva:larva,
          evaluador:profile.display_name,muestreados:embaladora,defectos_json:defectCounts,
          ...score,motivo:nota,...identity(profile)};
        table='muestreos_anden';
      }else if(kind==='proceso'){
        if(Object.values(defectCounts).reduce((a,b)=>a+b,0)>total)throw new Error('Los defectos superan el total de frutos');
        const manual=empacable.trim()===''?undefined:Number(empacable.replace(',','.'));
        if(manual===undefined||!Number.isFinite(manual)||manual<0||manual>100)throw new Error('Captura el porcentaje empacable manualmente, entre 0 y 100');
        const score=scoreProceso(defectCounts,total,box,t,manual);
        payload={uuid,fecha,cultivo:'Frambuesa',frutos_muestra:total,rancho,cajas:box,taras:t,...score,...identity(profile)};
        table='muestreos_proceso';
      }else{
        payload={uuid,fecha,cultivo:'Frambuesa',categoria,nivel,nota,...identity(profile)};
        table='semaforo';
      }
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
        setCounts({});setLarvas('0');setPeso('');setNota('');
        // Mantener rancho, sector, variedad, presentación, cuadrilla y embaladora.
      }else await onSaved();
    }catch(e){Alert.alert('Revisar captura',errorMessage(e));}finally{setSaving(false);}
  }
  return <><Text style={styles.heading}>{editing?'Modificar muestreo':kind==='anden'?'Muestreo de andén':kind==='proceso'?'Muestreo de proceso':'Semáforo'}</Text>
    <Text style={styles.subtitle}>Frambuesa · captura segura sin conexión</Text>
    {kind==='semaforo'?<><Input label="Categoría" value={categoria} onChange={setCategoria}/><Choice label="Nivel" options={['ok','warn','danger']} value={nivel} onChange={setNivel}/><Input label="Observaciones" value={nota} onChange={setNota}/></>:<>
      <Choice label="Rancho" options={ranchos} value={rancho} onChange={setRancho}/>
      {kind==='anden'&&<><Input label="Sector" value={sector} onChange={setSector}/><Choice label="Variedad" options={variedades} value={variedad} onChange={setVariedad}/><Choice label="Presentación" options={presentaciones.map(p=>p.name)} value={presentacion} onChange={setPresentacion}/><Input label="Cuadrilla" value={cuadrilla} onChange={setCuadrilla}/><Input label="Embaladora" value={embaladora} onChange={setEmbaladora}/><Input label="Peso en gramos" value={peso} onChange={setPeso} keyboard="numeric"/><Input label="Frutos con larva" value={larvas} onChange={setLarvas} keyboard="numeric"/></>}
      <Input label="Cajas" value={cajas} onChange={setCajas} keyboard="numeric"/>
      {kind==='proceso'&&<><Input label="Taras" value={taras} onChange={setTaras} keyboard="numeric"/><Text style={styles.notice}>Cada tara equivale a 3 kg.</Text><Input label="Potencial empacable (%) · captura obligatoria" value={empacable} onChange={setEmpacable} keyboard="numeric"/></>}
      <Input label="Frutos inspeccionados" value={frutos} onChange={setFrutos} keyboard="numeric"/>
      {kind==='anden'&&<Text style={styles.notice}>Canastos sugeridos: {canastosPorCajas(n(cajas))} (1 por cada 24 cajas o fracción)</Text>}
      <Text style={styles.section}>Defectos encontrados</Text>
      {defects.map(d=><View key={d.key} style={styles.defectRow}>
          <View style={{flex:1}}><Text style={styles.defectTitle}>{d.label}</Text><Text style={styles.defectCategory}>{d.category}</Text></View>
          <Pressable accessibilityLabel={'Restar '+d.label} onPress={()=>setCounts(prev=>({...prev,[d.key]:String(Math.max(0,n(prev[d.key]||'0')-1))}))} style={styles.counterButton}><Text style={styles.counterText}>−</Text></Pressable>
          <Text style={styles.counterValue}>{counts[d.key]||'0'}</Text>
          <Pressable accessibilityLabel={'Sumar '+d.label} onPress={()=>setCounts(prev=>({...prev,[d.key]:String(n(prev[d.key]||'0')+1)}))} style={styles.counterButton}><Text style={styles.counterText}>+</Text></Pressable>
        </View>)}
      {kind==='anden'&&<Input label="Observaciones" value={nota} onChange={setNota}/>}
       <View style={styles.card}>
         <Text style={styles.section}>Resumen del muestreo</Text>
         <Text style={styles.label}>Rancho: {rancho} · Frutos: {frutos} {kind==='anden'?'· Embaladora: '+(embaladora||'—'):''}</Text>
         {!validPreview&&<Text style={{color:C.danger}}>Revisa el total de frutos y defectos antes de guardar.</Text>}
         {andenPreview&&<><Text style={styles.label}>Condición: {(andenPreview.pct_condicion*100).toFixed(1)}% · Apariencia: {(andenPreview.pct_apariencia*100).toFixed(1)}%</Text><Text style={styles.label}>Resultado: {andenPreview.disposicion} · {andenPreview.puntos_total} puntos</Text></>}
         {procesoPreview&&<><Text style={styles.label}>Porcentaje de proceso: {procesoPreview.pct_proceso?.toFixed(1)??'—'}%</Text><Text style={styles.label}>Empacable (manual): {empacable||'Pendiente'}%</Text><Text style={styles.section}>Áreas de enfoque</Text>
           <Text>Agronomía: {procesoPreview.area_agronomia.toFixed(1)}% · Cosecha: {procesoPreview.area_cosecha.toFixed(1)}%</Text>
           <Text>Actividades: {procesoPreview.area_actividades.toFixed(1)}% · Inocuidad: {procesoPreview.area_inocuidad.toFixed(1)}%</Text></>}
         {defects.filter(d=>n(counts[d.key]||'0')>0).map(d=><Text key={d.key} style={styles.label}>{d.label}: {counts[d.key]} fruto(s) · {totalPreview>0?(n(counts[d.key]||'0')/totalPreview*100).toFixed(1):'—'}%</Text>)}
       </View>
    </>}
    {kind==='anden'&&!editing&&<Choice label="Después de guardar" options={['Volver al inicio','Otro andén con los mismos datos']} value={continueAnden?'Otro andén con los mismos datos':'Volver al inicio'} onChange={v=>setContinueAnden(v.startsWith('Otro'))}/>}
    <Button title={saving?'Guardando…':editing?'Revisar modificaciones':'Revisar y confirmar muestreo'} disabled={saving} onPress={()=>{
      const total=n(frutos);
      const counted=defects.reduce((s,d)=>s+n(counts[d.key]||'0'),0);
      const score=kind==='anden'&&total>0?scoreAnden(Object.fromEntries(defects.map(d=>[d.key,n(counts[d.key]||'0')])),total,n(larvas)):null;
      const summary=['Rancho: '+rancho,'Frutos inspeccionados: '+total,'Defectos contados: '+counted,kind==='anden'?'Embaladora: '+(embaladora||'Sin especificar'):'Taras: '+taras+' (3 kg c/u)',kind==='anden'?'Resultado: '+(score?.disposicion||'Pendiente'):'Empacable manual: '+(empacable||'Sin capturar')+'%'].join('\n');
      Alert.alert('Confirmar muestreo',summary+'\n\n¿Confirmas guardar este registro?',[
        {text:'Revisar',style:'cancel'},
        {text:editing?'Guardar cambios':'Confirmar y guardar',onPress:()=>{void save();}}
      ]);
    }}/>
  </>;
}
const styles=StyleSheet.create({
  dropdownHeader:{flexDirection:'row',alignItems:'center',justifyContent:'space-between',backgroundColor:C.white,borderWidth:1,borderColor:C.line,borderRadius:14,paddingVertical:16,paddingHorizontal:17},
  dropdownValue:{fontSize:16,color:C.ink,fontStyle:'italic',flex:1},
  dropdownArrow:{fontSize:24,color:C.burgundy,marginLeft:12},
  dropdownOptions:{backgroundColor:C.white,borderWidth:1,borderColor:C.line,borderRadius:14,marginTop:5,overflow:'hidden'},
  dropdownOption:{flexDirection:'row',justifyContent:'space-between',alignItems:'center',paddingVertical:13,paddingHorizontal:17,borderBottomWidth:StyleSheet.hairlineWidth,borderBottomColor:C.line},
  dropdownOptionSelected:{backgroundColor:'#FFF2DE'},
  dropdownOptionText:{fontSize:15,color:C.ink,flex:1},
  moduleTile:{flexDirection:'row',alignItems:'center',backgroundColor:C.white,borderWidth:1,borderColor:C.line,borderRadius:17,padding:17,marginBottom:12,gap:14},
  moduleIcon:{fontSize:27,width:40,textAlign:'center'},moduleTitle:{fontSize:19,fontWeight:'700',color:C.ink},moduleDescription:{fontSize:12,color:C.muted,marginTop:4,lineHeight:18},moduleArrow:{fontSize:28,color:C.gold},
  defectRow:{flexDirection:'row',alignItems:'center',backgroundColor:'#FFFFFF',borderWidth:1,borderColor:'#DDDCD6',borderRadius:18,paddingVertical:22,paddingHorizontal:14,marginBottom:12,gap:8},
  defectTitle:{fontSize:15,fontWeight:'600',color:C.ink},defectCategory:{fontSize:11,color:C.muted,marginTop:3},
  counterButton:{width:38,height:44,alignItems:'center',justifyContent:'center',borderRadius:10,backgroundColor:'#F5F7F2'},
  counterText:{fontSize:30,color:'#145D3B',fontWeight:'600'},counterValue:{minWidth:28,textAlign:'center',fontSize:19,fontWeight:'800',color:C.ink},
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
