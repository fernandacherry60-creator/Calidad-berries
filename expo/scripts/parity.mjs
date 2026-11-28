import assert from 'node:assert/strict';
import { andenDefects, procesoDefects, scoreAnden, scoreProceso } from '../src/lib/rules.ts';

// Fixtures calculated with the original Flutter engine (berrys/lib/core/scoring.dart)
// using the same 100-fruit samples. The only approved process difference is
// tare mass: Flutter 2.6 kg; QUALYX Expo 3 kg.
const andenCounts = {
  'Podrido': 2,
  'Verde': 3,
  'Quebrada': 2,
  'Picada de pajaro': 1,
};
const originalAnden = {
  pct_condicion: 2,
  pct_apariencia: 6,
  puntos_condicion: 50,
  puntos_apariencia: 25,
  puntos_total: 75,
  disposicion: 'PASO',
};
const expoAnden = scoreAnden(andenCounts, 100, 0);
for (const [key, expected] of Object.entries(originalAnden)) {
  assert.equal(expoAnden[key], expected, 'Andenes parity: ' + key);
}
assert.equal(andenDefects.length, 21, 'Expo Andenes includes the approved bird-excreta safety rule.');

const processCounts = {
  'Verde': 4,
  'Quebrada': 2,
  'Fumagina': 1,
  'Suciedad': 3,
};
const originalProcess = {
  area_cosecha: 6,
  area_agronomia: 1,
  area_actividades: 0,
  area_inocuidad: 3,
  area_poscosecha: 0,
  total_defectos: 10,
  potencial_empacable: 6,
};
const expoProcess = scoreProceso(processCounts, 100, 24, 2);
for (const [key, expected] of Object.entries(originalProcess)) {
  assert.equal(expoProcess[key], expected, 'Proceso parity: ' + key);
}
assert.equal(procesoDefects.length, 25, 'The process catalogue must match the original 25 defects.');
for (const removed of ['Fruta buena', 'Botrytis', 'Deshidratada', 'Excreta de pajaro']) {
  assert.equal(procesoDefects.some(d => d.key === removed), false, 'Removed extra defect: ' + removed);
}

// Explicitly document and test the approved tare-weight change.
const flutterPct = (2 * 2.6) / (24 * 2.23 + 2 * 2.6) * 100;
const expoPct = expoProcess.pct_proceso;
assert.ok(expoPct !== null);
assert.ok(Math.abs(expoPct - 10.080645161290322) < 1e-9);
assert.ok(Math.abs(flutterPct - 8.855245683930943) < 1e-9);
console.log('PASS: Andenes and process scoring parity; 25-defect catalogue; approved 3 kg Expo tare difference.');
