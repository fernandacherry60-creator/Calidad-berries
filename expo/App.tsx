import React, { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Alert, AppState, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import * as Linking from 'expo-linking';
import * as Crypto from 'expo-crypto';
import NetInfo from '@react-native-community/netinfo';
import { supabase, loadProfile, redeemPendingInvitation, type Profile } from './src/lib/cloud';
import { savePending, saveSample, syncSamples, localSamples, pendingCount, cacheVerifiedProfile, getCachedProfile, clearCachedProfile, type TableName, type LocalSample } from './src/lib/offline';
import { andenDefects, procesoDefects, scoreAnden, scoreProceso, ranchos, variedades, presentaciones, puestos, canastosPorCajas } from './src/lib/rules';

type Screen = 'home'|'team'|'history'|'anden'|'proceso'|'semaforo';
const C = { ink:'#24332D', green:'#28764C', cream:'#F8F7F2', muted:'#65766D', line:'#E3E8E2', white:'#FFFFFF', danger:'#B83C46' };
const fieldStyle = { borderWidth:1,borderColor:C.line,borderRadius:12,padding:12,backgroundColor:C.white,fontSize:15,color:C.ink } as const;
const Button = ({title,onPress,disabled=false}: {title:string;onPress:()=>void;disabled?:boolean}) =>
  <Pressable disabled={disabled} onPress={onPress} style={[styles.button,disabled&&{opacity:.5}]}><Text style={styles.buttonText}>{title}</Text></Pressable>;
const Input = ({label,value,onChange,secure=false,keyboard='default'}: {label:string;value:string;onChange:(v:string)=>void;secure?:boolean;keyboard?:'default'|'numeric'|'email-address'}) =>
  <View style={{marginBottom:12}}><Text style={styles.label}>{label}</Text><TextInput autoCapitalize={keyboard==='email-address'?'none':'sentences'} secureTextEntry={secure} keyboardType={keyboard} style={fieldStyle} value={value} onChangeText={onChange}/></View>;
const Choice = ({label,options,value,onChange}: {label:string;options:string[];value:string;onChange:(v:string)=>void}) =>
  <View style={{marginBottom:12}}><Text style={styles.label}>{label}</Text><View style={styles.choices}>{options.map(v=><Pressable key={v} onPress={()=>onChange(v)} style={[styles.chip,value===v&&styles.selected]}><Text style={{color:value===v?C.white:C.ink}}>{v}</Text></Pressable>)}</View></View>;
const errorMessage = (e:unknown) => e instanceof Error?e.message:String(e);
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
  const [screen,setScreen]=useState<Screen>('home');
  const [panel,setPanel]=useState<'admin'|'worker'>('admin');
  const [pending,setPending]=useState(0);
  const [features,setFeatures]=useState<Record<string,boolean>>({enable_sampling:true,enable_semaforo:true,enable_cloud_sync:true});
  const refresh=useCallback(async()=>{
    const {data:{session}}=await supabase.auth.getSession();
    const user=session?.user;
    if(!user){setUserId(null);setProfile(null);return;}
    setUserId(user.id);
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
  async function logout(){await supabase.auth.signOut();await clearCachedProfile();setProfile(null);setUserId(null);setScreen('home');}
  if(busy)return <View style={styles.center}><ActivityIndicator color={C.green} size="large"/></View>;
  if(recovering)return <ResetPasswordView onComplete={async()=>{setRecovering(false);await supabase.auth.signOut();await refresh();}}/>;
  if(!userId||!profile)return <AuthView userId={userId} onDone={refresh} onLogout={logout} onPanel={setPanel}/>;
  const navigate=(next:Screen)=>setScreen(next);
  const dualPanel=profile.role==='admin'&&profile.email.toLowerCase()==='yamilethklunder@gmail.com';
  const adminPanel=profile.role==='admin'&&(!dualPanel||panel==='admin');
  return <View style={styles.page}>
    <View style={styles.top}><Text style={styles.topTitle}>Calidad Berries Pro</Text><Text style={styles.topSmall}>{profile.display_name} · {adminPanel?'Administradora':'Trabajadora'}</Text></View>
    <ScrollView contentContainerStyle={styles.body}>
      {screen!=='home'&&<Pressable onPress={()=>navigate('home')}><Text style={styles.back}>‹ Volver al inicio</Text></Pressable>}
      {screen==='home'&&<>
        {dualPanel&&<Choice label="Panel de trabajo" options={['Administradora','Trabajadora']} value={panel==='admin'?'Administradora':'Trabajadora'} onChange={v=>setPanel(v==='Administradora'?'admin':'worker')}/>}
        <Text style={styles.heading}>Control de calidad</Text>
        <Text style={styles.subtitle}>Captura offline y sincronización segura con Supabase</Text>
        <View style={styles.card}><Text style={styles.label}>Registros pendientes en este teléfono</Text><Text style={styles.big}>{pending}</Text>
          <Button title="Sincronizar ahora" onPress={async()=>{try{const r=await syncSamples(profile);setPending(r.pending);Alert.alert('Sincronización',`Subidos: ${r.uploaded}. Pendientes: ${r.pending}`);}catch(e){Alert.alert('Sin conexión',errorMessage(e));}}}/></View>
        {features.enable_sampling!==false&&<><Button title="Nuevo muestreo de andén" onPress={()=>navigate('anden')}/><Button title="Nuevo muestreo de proceso" onPress={()=>navigate('proceso')}/></>}
        {features.enable_semaforo!==false&&<Button title="Nuevo semáforo" onPress={()=>navigate('semaforo')}/>}
        <Button title="Historial de este teléfono" onPress={()=>navigate('history')}/>
        {adminPanel&&<Button title="Trabajadores y muestreos en la nube" onPress={()=>navigate('team')}/>}
        <Pressable onPress={logout}><Text style={styles.logout}>Cerrar sesión</Text></Pressable>
      </>}
      {screen==='team'&&adminPanel&&<TeamView/>}
      {screen==='history'&&<HistoryView profile={profile}/>}
      {(screen==='anden'||screen==='proceso'||screen==='semaforo')&&<CaptureView kind={screen} profile={profile} onSaved={async()=>{setPending(await pendingCount(profile.user_id));navigate('home');}}/>}
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
      <View style={styles.entryCherry}><Text style={styles.entryCherryText}>🍒</Text></View>
      <Text style={styles.entryBrand}>Calidad Berries</Text>
      <Text style={styles.entryBrandPro}>Pro</Text>
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
          {userId&&<Text style={styles.notice}>Hay una sesión sin perfil activo. Confirma tu correo o cierra sesión.</Text>}

          <Input label="Correo electrónico" value={email} onChange={setEmail} keyboard="email-address"/>
          <Input label="Contraseña (mínimo 8 caracteres)" value={password} onChange={setPassword} secure/>
          <Button title={working?'Procesando…':'Ingresar'} disabled={working||password.length<8||!email.includes('@')} onPress={submit}/>
          <Pressable onPress={async()=>{const normalized=email.trim().toLowerCase();if(!normalized.includes('@')){Alert.alert('Recuperar acceso','Escribe primero tu correo electrónico.');return;}setWorking(true);try{const {error}=await supabase.auth.resetPasswordForEmail(normalized,{redirectTo:'calidadberriespro://auth-callback'});if(error)throw error;Alert.alert('Revisa tu correo','Abre el enlace de recuperación en este teléfono y escribe tu nueva contraseña en la aplicación.');}catch(e){Alert.alert('Recuperación',errorMessage(e));}finally{setWorking(false);}}} style={styles.entryRegister}><Text style={styles.entryRegisterText}>Olvidé mi contraseña</Text></Pressable>
          {userId&&<Button title="Cerrar sesión" onPress={onLogout}/>}
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
    <Text style={styles.entryBrand}>Calidad Berries</Text><Text style={styles.entryBrandPro}>Pro</Text>
    <View style={styles.entryLoginCard}><Text style={styles.entryLoginTitle}>Establecer contraseña nueva</Text>
      <Text style={styles.entryLoginHint}>El enlace de recuperación ya abrió una sesión temporal. Guarda aquí tu nueva contraseña.</Text>
      <Input label="Contraseña nueva (mínimo 8 caracteres)" value={password} onChange={setPassword} secure/>
      <Input label="Confirmar contraseña" value={confirm} onChange={setConfirm} secure/>
      <Button title={saving?'Guardando…':'Guardar contraseña'} disabled={saving||password.length<8||password!==confirm} onPress={async()=>{
        setSaving(true);try{const {error}=await supabase.auth.updateUser({password});if(error)throw error;Alert.alert('Contraseña actualizada','Ya puedes iniciar sesión con tu contraseña nueva.',[{text:'Continuar',onPress:()=>void onComplete()}]);}catch(e){Alert.alert('No se pudo actualizar',errorMessage(e));}finally{setSaving(false);}
      }}/>
    </View></View></ScrollView>;
}
function TeamView(){
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
        const result=await supabase.from(table).select('uuid,fecha,usuario_nombre,usuario_email,cultivo').order('fecha',{ascending:false}).limit(50);
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
    {samples.map(m=><View key={String(m.uuid)} style={styles.card}><Text style={styles.label}>{String(m.tipo)} · {String(m.cultivo)}</Text><Text>{String(m.usuario_nombre||m.usuario_email||'Sin nombre')}</Text><Text>{String(m.fecha)}</Text></View>)}
  </>;
}
function HistoryView({profile}:{profile:Profile}){
  const [rows,setRows]=useState<LocalSample[]>([]);
  useEffect(()=>{void localSamples(profile.user_id).then(setRows).catch(e=>Alert.alert('Historial',errorMessage(e)));},[profile.user_id]);
  return <><Text style={styles.heading}>Historial local</Text>{rows.length===0&&<Text>Sin registros en este teléfono</Text>}
    {rows.map(row=><View key={row.uuid} style={styles.card}><Text style={styles.label}>{row.table_name}</Text><Text>{row.fecha}</Text><Text style={{color:row.synced?C.green:C.danger}}>{row.synced?'Sincronizado':'Pendiente'}</Text></View>)}</>;
}
function CaptureView({kind,profile,onSaved}:{kind:'anden'|'proceso'|'semaforo';profile:Profile;onSaved:()=>Promise<void>}){
  const [rancho,setRancho]=useState(ranchos[0]),[sector,setSector]=useState(''),[variedad,setVariedad]=useState(variedades[0]);
  const [presentacion,setPresentacion]=useState(presentaciones[0].name),[cuadrilla,setCuadrilla]=useState('');
  const [cajas,setCajas]=useState('0'),[taras,setTaras]=useState('0'),[frutos,setFrutos]=useState('100');
  const [larvas,setLarvas]=useState('0'),[peso,setPeso]=useState(''),[brix,setBrix]=useState('');
  const [licencia,setLicencia]=useState(''),[embaladora,setEmbaladora]=useState(''),[nota,setNota]=useState('');
  const [categoria,setCategoria]=useState('Condición'),[nivel,setNivel]=useState('ok');
  const [counts,setCounts]=useState<Record<string,string>>({});
  const [saving,setSaving]=useState(false);
  const defects=kind==='anden'?andenDefects:procesoDefects;
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
          cajas_recibidas:box,canastos:canastosPorCajas(box),fruta_muestra:total,licencia,
          grados_brix:brix?n(brix):null,peso:peso?n(peso):null,frutos_larva:larva,
          evaluador:profile.display_name,muestreados:embaladora,defectos_json:defectCounts,
          ...score,motivo:nota,...identity(profile)};
        table='muestreos_anden';
      }else if(kind==='proceso'){
        if(Object.values(defectCounts).reduce((a,b)=>a+b,0)>total)throw new Error('Los defectos superan el total de frutos');
        const score=scoreProceso(defectCounts,total,box,t);
        payload={uuid,fecha,cultivo:'Frambuesa',frutos_muestra:total,rancho,cajas:box,taras:t,...score,...identity(profile)};
        table='muestreos_proceso';
      }else{
        payload={uuid,fecha,cultivo:'Frambuesa',categoria,nivel,nota,...identity(profile)};
        table='semaforo';
      }
      await saveSample(table,payload,profile.user_id);
      Alert.alert('Guardado','Registro almacenado en el teléfono. Se sincronizará al tener conexión.');
      await onSaved();
    }catch(e){Alert.alert('Revisar captura',errorMessage(e));}finally{setSaving(false);}
  }
  return <><Text style={styles.heading}>{kind==='anden'?'Muestreo de andén':kind==='proceso'?'Muestreo de proceso':'Semáforo'}</Text>
    <Text style={styles.subtitle}>Frambuesa · captura segura sin conexión</Text>
    {kind==='semaforo'?<><Input label="Categoría" value={categoria} onChange={setCategoria}/><Choice label="Nivel" options={['ok','warn','danger']} value={nivel} onChange={setNivel}/><Input label="Observaciones" value={nota} onChange={setNota}/></>:<>
      <Choice label="Rancho" options={ranchos} value={rancho} onChange={setRancho}/>
      {kind==='anden'&&<><Input label="Sector" value={sector} onChange={setSector}/><Choice label="Variedad" options={variedades} value={variedad} onChange={setVariedad}/><Choice label="Presentación" options={presentaciones.map(p=>p.name)} value={presentacion} onChange={setPresentacion}/><Input label="Cuadrilla" value={cuadrilla} onChange={setCuadrilla}/><Input label="Licencia" value={licencia} onChange={setLicencia}/><Input label="Embaladora" value={embaladora} onChange={setEmbaladora}/><Input label="Grados Brix" value={brix} onChange={setBrix} keyboard="numeric"/><Input label="Peso en gramos" value={peso} onChange={setPeso} keyboard="numeric"/><Input label="Frutos con larva" value={larvas} onChange={setLarvas} keyboard="numeric"/></>}
      <Input label="Cajas" value={cajas} onChange={setCajas} keyboard="numeric"/>
      {kind==='proceso'&&<Input label="Taras" value={taras} onChange={setTaras} keyboard="numeric"/>}
      <Input label="Frutos inspeccionados" value={frutos} onChange={setFrutos} keyboard="numeric"/>
      {kind==='anden'&&<Text style={styles.notice}>Canastos sugeridos: {canastosPorCajas(n(cajas))} (1 por cada 24 cajas o fracción)</Text>}
      <Text style={styles.section}>Defectos encontrados</Text>
      {defects.map(d=><Input key={d.key} label={d.label+' · '+d.category} value={counts[d.key]||'0'} onChange={v=>setCounts(prev=>({...prev,[d.key]:v}))} keyboard="numeric"/>)}
      {kind==='anden'&&<Input label="Observaciones" value={nota} onChange={setNota}/>}
    </>}
    <Button title={saving?'Guardando…':'Guardar muestreo sin conexión'} disabled={saving} onPress={save}/>
  </>;
}
const styles=StyleSheet.create({
  page:{flex:1,backgroundColor:C.cream},body:{padding:20,paddingBottom:60},
  top:{backgroundColor:C.green,paddingHorizontal:20,paddingTop:58,paddingBottom:20},
  topTitle:{fontSize:23,fontWeight:'800',color:C.white},topSmall:{color:'#D9F2E4',marginTop:5},
  center:{flex:1,alignItems:'center',justifyContent:'center'},
  auth:{flexGrow:1,justifyContent:'center',padding:24,backgroundColor:C.cream},
  entryPage:{flexGrow:1,justifyContent:'space-between',paddingHorizontal:28,paddingTop:60,paddingBottom:30,backgroundColor:'#F9F8F3'},
  entryCenter:{flex:1,justifyContent:'center',alignItems:'center',width:'100%',maxWidth:460,alignSelf:'center'},
  entryCherry:{height:92,width:92,borderRadius:46,backgroundColor:'#FDE9E8',alignItems:'center',justifyContent:'center',marginBottom:16},
  entryCherryText:{fontSize:52},
  entryBrand:{fontSize:43,fontStyle:'italic',fontFamily:'serif',fontWeight:'700',color:'#B82F62',textAlign:'center',letterSpacing:-1},
  entryBrandPro:{fontSize:32,fontStyle:'italic',fontFamily:'serif',color:'#C49A3A',marginTop:-6,textAlign:'center'},
  entryRule:{width:65,height:2,backgroundColor:'#C49A3A',marginTop:23,marginBottom:34},
  entryPrimary:{backgroundColor:'#286D4D',paddingVertical:19,borderRadius:17,width:'100%',alignItems:'center',marginBottom:14},
  entryPrimaryText:{color:'#FFFFFF',fontSize:17,fontWeight:'800'},
  entrySecondary:{backgroundColor:'#FFFFFF',borderColor:'#BBD0C0',borderWidth:1.5,paddingVertical:19,borderRadius:17,width:'100%',alignItems:'center'},
  entrySecondaryText:{color:'#286D4D',fontSize:17,fontWeight:'800'},
  entryBack:{alignSelf:'flex-start',paddingVertical:10,marginBottom:8},
  entryBackText:{color:'#286D4D',fontWeight:'700',fontSize:14},
  entryLoginCard:{width:'100%',backgroundColor:'#FFFFFF',borderRadius:22,padding:20,borderWidth:1,borderColor:'#E3EAE2'},
  entryLoginTitle:{fontSize:21,fontWeight:'800',color:'#244934',marginBottom:5},
  entryLoginHint:{fontSize:13,color:'#687B70',marginBottom:20,lineHeight:19},
  entryRegister:{alignItems:'center',padding:10},
  entryRegisterText:{color:'#286D4D',fontWeight:'700',fontSize:13},
  entryFooter:{textAlign:'center',fontSize:10,letterSpacing:1.3,color:'#8B988D',fontWeight:'700',marginTop:20},
  authModern:{flexGrow:1,backgroundColor:'#F4F7F3'},
  authHero:{minHeight:320,backgroundColor:'#153E30',paddingHorizontal:26,paddingTop:62,paddingBottom:30,overflow:'hidden',position:'relative'},
  authOrbLarge:{position:'absolute',width:300,height:300,borderRadius:150,backgroundColor:'#245B43',right:-130,top:-80},
  authOrbSmall:{position:'absolute',width:185,height:185,borderRadius:100,backgroundColor:'#2D6A4B',right:-70,bottom:-120},
  authTopline:{flexDirection:'row',alignItems:'center',gap:10},
  authBrandMark:{width:42,height:42,borderRadius:13,backgroundColor:'#D4EDC7',alignItems:'center',justifyContent:'center'},
  authBrandMarkText:{color:'#164332',fontWeight:'900',fontSize:16},
  authEdition:{color:'#DBF0E2',fontSize:11,fontWeight:'800',letterSpacing:2},
  authHeroContent:{marginTop:30},
  authEyebrow:{color:'#B6DDBB',fontSize:10,fontWeight:'800',letterSpacing:1.6,marginBottom:12},
  authHeroTitle:{color:'#FFFFFF',fontSize:31,fontWeight:'900',lineHeight:37,letterSpacing:-.7},
  authHeroDesc:{color:'#D1E6D9',fontSize:13,lineHeight:20,marginTop:12,maxWidth:310},
  authHeroTags:{flexDirection:'row',flexWrap:'wrap',gap:7,marginTop:20},
  authHeroTag:{color:'#E0F3E6',backgroundColor:'#FFFFFF20',borderColor:'#FFFFFF30',borderWidth:1,overflow:'hidden',borderRadius:20,paddingHorizontal:10,paddingVertical:6,fontSize:11,fontWeight:'600'},
  authContent:{paddingHorizontal:23,paddingTop:26,paddingBottom:36},
  authWelcome:{fontSize:24,fontWeight:'900',color:'#183C2D',letterSpacing:-.5},
  authLead:{fontSize:13,color:'#607369',marginTop:7,marginBottom:22,lineHeight:20},
  authForm:{backgroundColor:'#FFFFFF',borderRadius:22,padding:19,borderWidth:1,borderColor:'#E2EBE3',marginBottom:18},
  authFooter:{textAlign:'center',color:'#809488',fontSize:10,fontWeight:'700',letterSpacing:1.2,marginBottom:14},
  brand:{fontSize:30,fontWeight:'900',color:C.green,marginBottom:6},
  heading:{fontSize:23,fontWeight:'800',color:C.ink,marginBottom:8},
  subtitle:{fontSize:14,color:C.muted,marginBottom:20},
  section:{fontSize:18,fontWeight:'800',color:C.ink,marginVertical:14},
  label:{fontSize:14,fontWeight:'700',color:C.ink,marginBottom:7},
  card:{backgroundColor:C.white,borderRadius:16,padding:16,marginBottom:14,borderWidth:1,borderColor:C.line},
  button:{backgroundColor:C.green,borderRadius:12,padding:15,alignItems:'center',marginBottom:12},
  buttonText:{fontSize:15,fontWeight:'800',color:C.white},
  big:{fontSize:30,fontWeight:'900',color:C.green,marginVertical:6},
  choices:{flexDirection:'row',flexWrap:'wrap',gap:7},
  chip:{paddingHorizontal:11,paddingVertical:10,borderWidth:1,borderColor:C.line,borderRadius:10,backgroundColor:C.white},
  selected:{backgroundColor:C.green,borderColor:C.green},
  notice:{padding:12,backgroundColor:'#F0F6F0',borderRadius:10,marginBottom:16,color:C.ink},
  logout:{color:C.danger,textAlign:'center',fontWeight:'700',padding:16},
  back:{color:C.green,fontWeight:'700',marginBottom:20},
});
