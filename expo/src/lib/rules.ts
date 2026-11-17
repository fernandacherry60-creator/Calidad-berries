// Migración de las reglas del motor Flutter v1.5 (lib/core/scoring.dart).
export const ranchos = ['ALEGRE 1','ALEGRE 3','ALEGRE 4','NOGAL','DERRAMADERO','BLANCO','CATARINA'];
export const variedades = ['MYA','MARILYN','FRYDA'];
export const puestos = ['Encargado de rancho','Supervisor','Gerente'];
export const presentaciones = [
  { name: '4.4 oz (Pollitos)', min: 160, max: 164 },
  { name: '6 oz', min: 198, max: 202 },
  { name: '8 oz (Corazon)', min: 279, max: 282 },
  { name: '9 oz', min: 322, max: 325 },
  { name: '12 oz', min: 396, max: 400 },
  { name: '18 oz', min: 574, max: 578 },
];
export type Defect = { key: string; label: string; category: string; points?: number };
export const andenDefects: Defect[] = [
  ['Podrido','Podrido','condicion'],['Humedo Sangrante','Húmedo Sangrante','condicion'],
  ['Colapsada / Blanda','Colapsada / Blanda','condicion'],['Fumagina','Fumagina','condicion'],
  ['Roya','Roya','condicion'],['Sobre Maduro','Sobre Maduro','condicion'],
  ['Cenicilla','Cenicilla','condicion'],['Verde','Verde','apariencia',15],
  ['Quebrada','Quebrada','apariencia',15],['Picada de pajaro','Picada de pájaro','apariencia'],
  ['Suciedad','Suciedad','apariencia'],['Quemadura de sol','Quemadura de sol','apariencia'],
  ['Dano de viento','Daño de viento','apariencia'],['Residuo de aplicacion','Residuo de aplicación','apariencia'],
  ['Dano de chinche','Daño de chinche','apariencia'],['Dano de trips','Daño de trips','apariencia'],
  ['Pelicula blanca','Película blanca','apariencia'],['Avejigada','Avejigada','apariencia'],
  ['Malformada','Malformada','apariencia'],['Extra chica','Extra chica','apariencia'],
].map(([key,label,category,points])=>({key:String(key),label:String(label),category:String(category),points:points?Number(points):0}));
export const procesoDefects: Defect[] = [
  ['Pudricion / Hongo','Podrición / hongo','Cosecha'],['Sangrante','Exudación / Sangrante','Cosecha'],
  ['Colapsada','Colapsada / blanda','Cosecha'],['Sobre maduro','Sobre maduro','Cosecha'],
  ['Verde','Verde','Cosecha'],['Quebrada','Quebrada','Cosecha'],
  ['Insectos / larva','Insecto / larva','Cosecha'],['Fumagina','Fumagina','Agronomia'],
  ['Roya','Roya','Agronomia'],['Cenicilla','Cenicilla','Agronomia'],
  ['Avejigada','Avejigada','Agronomia'],['Mal formada','Malformada','Agronomia'],
  ['Extra chico','Extra chica','Agronomia'],['Bicolor','Bicolor','Agronomia'],
  ['Residuo de aplicacion','Residuo de aplicación','Agronomia'],
  ['Dano por chinche','Daño de chinche','Agronomia'],['Dano de trips','Daño de trips','Agronomia'],
  ['Pelicula blanca','Película blanca','Agronomia'],['Desgranada','Desgranada','Agronomia'],
  ['Picado de ave','Picada de pájaro','Actividades'],['Quemadura de sol','Quemadura de sol','Actividades'],
  ['Dano por viento','Daño de viento','Actividades'],['Dano mecanico','Daño mecánico','Actividades'],
  ['Suciedad','Suciedad','Inocuidad'],['Materia extrana','Materia extraña','Inocuidad'],
].map(([key,label,category])=>({key:String(key),label:String(label),category:String(category)}));
export const canastosPorCajas = (cajas: number) => cajas<=0?0:Math.ceil(cajas/24);
export function scoreAnden(counts: Record<string,number>, total: number, larvas=0) {
  if (!Number.isFinite(total) || total<=0) throw new Error('La muestra debe contener frutos');
  let condicion=0, apariencia=0, puntosApariencia=0;
  for (const defect of andenDefects) {
    const pct=(counts[defect.key]||0)/total;
    if(defect.category==='condicion') condicion+=pct;
    else {
      apariencia+=pct;
      if(defect.points) puntosApariencia+=Math.max(0,defect.points-Math.floor(pct*100));
    }
  }
  const puntosCondicion=condicion<=0.05+1e-9?50:0;
  const puntosTotal=puntosCondicion+puntosApariencia;
  const decimas=Math.round(apariencia*1000);
  const disposicion=condicion>0.05+1e-9||decimas>=156||larvas>=2||puntosTotal<60
    ?'RECHAZO':decimas>=150||larvas===1?'REEMPAQUE':'PASO';
  return { pct_condicion:condicion,pct_apariencia:apariencia,
    puntos_condicion:puntosCondicion,puntos_apariencia:puntosApariencia,
    puntos_total:puntosTotal,disposicion };
}
export function scoreProceso(counts: Record<string,number>, total: number, cajas: number, taras: number) {
  if(total<=0) throw new Error('La muestra debe contener frutos');
  const percentages:Record<string,number>={};
  const areas:Record<string,number>={Agronomia:0,Poscosecha:0,Cosecha:0,Actividades:0,Inocuidad:0};
  let totalDefectos=0;
  for(const d of procesoDefects) {
    const pct=(counts[d.key]||0)/total*100;
    percentages[d.key]=pct;areas[d.category]+=pct;totalDefectos+=pct;
  }
  const potencial=['Verde','Quebrada','Mal formada','Extra chico']
    .reduce((sum,key)=>sum+(percentages[key]||0),0);
  const kg=cajas*2.23+taras*2.6;
  return { defectos_json:percentages,area_agronomia:areas.Agronomia,
    area_poscosecha:areas.Poscosecha,area_cosecha:areas.Cosecha,
    area_actividades:areas.Actividades,area_inocuidad:areas.Inocuidad,
    total_defectos:Math.min(100,totalDefectos),potencial_empacable:Math.min(100,potencial),
    pct_proceso:kg>0?taras*2.6/kg*100:null };
}
