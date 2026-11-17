import 'package:calidad_berries/core/constants.dart';
import 'package:calidad_berries/core/scoring.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pruebas del motor de negocio (v1.5).
///
/// Corren con `flutter test` y NO necesitan emulador ni telefono: solo
/// tocan logica pura, nada de UI ni de base de datos.
///
/// Por que existen: las reglas de esta app las define la clienta por
/// WhatsApp y cambian cada pocas semanas (el umbral de apariencia ya
/// cambio tres veces). Cada vez que se mueve un numero, esta suite dice
/// en dos segundos si se rompio algo mas.
void main() {
  group('canastosPorCajas (v1.5: redondeo hacia arriba)', () {
    test('los tres ejemplos que dio la clienta el 25/ago', () {
      expect(canastosPorCajas(24), 1);
      expect(canastosPorCajas(48), 2);
      expect(canastosPorCajas(62), 3);
    });

    test('cada grupo de 24 o fraccion lleva canasto', () {
      // Con la division hacia abajo de v1.4 estos daban 2, 0 y 0.
      expect(canastosPorCajas(50), 3);
      expect(canastosPorCajas(1), 1);
      expect(canastosPorCajas(23), 1);
    });

    test('sin cajas no hay canastos', () {
      expect(canastosPorCajas(0), 0);
      expect(canastosPorCajas(-5), 0);
    });
  });

  group('veredictoApariencia (banda del 25/ago)', () {
    test('hasta 14.9% pasa', () {
      expect(veredictoApariencia(0.149), 'PASO');
      expect(veredictoApariencia(29 / 200), 'PASO'); // 14.5%
    });

    test('de 15.0% a 15.5% es reempaque', () {
      expect(veredictoApariencia(0.15), 'REEMPAQUE');
      expect(veredictoApariencia(30 / 200), 'REEMPAQUE'); // 15.0%
      expect(veredictoApariencia(31 / 200), 'REEMPAQUE'); // 15.5%
      expect(veredictoApariencia(155 / 1000), 'REEMPAQUE');
    });

    test('desde 15.6% es rechazo', () {
      expect(veredictoApariencia(156 / 1000), 'RECHAZO');
      expect(veredictoApariencia(32 / 200), 'RECHAZO'); // 16.0%
      expect(veredictoApariencia(0.50), 'RECHAZO');
    });

    test('el 15% exacto no se escapa por punto flotante', () {
      // 10/100 + 5/100 da 0.15000000000000002 en punto flotante: este
      // era el caso que obligaba a arrastrar un epsilon en v1.4.
      expect(veredictoApariencia(0.10 + 0.05), 'REEMPAQUE');
    });

    test('con muestra que no es de 100 frutos la banda sigue existiendo', () {
      // El riesgo real de la regla vieja: si el reempaque solo fuera el
      // 15% clavado, con 200 frutos 30 seria reempaque y 31 ya rechazo.
      expect(veredictoApariencia(30 / 200), 'REEMPAQUE');
      expect(veredictoApariencia(31 / 200), 'REEMPAQUE');
    });
  });

  group('calcularScoreAnden', () {
    // 'Suciedad' es de apariencia y no otorga puntos: sirve para mover
    // el % de apariencia sin ensuciar la calificacion.
    ResultadoScore conSuciedad(int conteo, int total) => calcularScoreAnden(
          conteos: {'Suciedad': conteo},
          totalFrutos: total,
        );

    test('muestra limpia: PASO con 80 puntos', () {
      final r = calcularScoreAnden(conteos: const {}, totalFrutos: 100);
      expect(r.disposicion, 'PASO');
      expect(r.puntosTotal, 80);
      expect(r.motivo, '');
    });

    test('apariencia en la banda: REEMPAQUE', () {
      final r = conSuciedad(30, 200); // 15.0%
      expect(r.disposicion, kDispReempaqueInterno);
      expect(etiquetaDisposicion(r.disposicion), 'REEMPAQUE');
    });

    test('apariencia arriba de la banda: RECHAZO', () {
      final r = conSuciedad(32, 200); // 16.0%
      expect(r.disposicion, 'RECHAZO');
    });

    test('condicion arriba de 5%: RECHAZO y cero puntos de condicion', () {
      final r = calcularScoreAnden(
        conteos: const {'Podrido': 11}, // 5.5%
        totalFrutos: 200,
      );
      expect(r.disposicion, 'RECHAZO');
      expect(r.puntosCondicion, 0);
    });

    test('condicion en 5% clavado todavia pasa', () {
      final r = calcularScoreAnden(
        conteos: const {'Podrido': 10}, // 5.0%
        totalFrutos: 200,
      );
      expect(r.puntosCondicion, kPuntosCondicion);
      expect(r.disposicion, 'PASO');
    });

    test('1 fruto con larva es reempaque, 2 son rechazo', () {
      final uno = calcularScoreAnden(
          conteos: const {}, totalFrutos: 100, frutosLarva: 1);
      expect(uno.disposicion, kDispReempaqueInterno);

      final dos = calcularScoreAnden(
          conteos: const {}, totalFrutos: 100, frutosLarva: 2);
      expect(dos.disposicion, 'RECHAZO');
    });

    test('menos de 60 puntos es rechazo', () {
      // Verde al 11% deja 4 puntos de 15; Quebrada al 11% otros 4.
      final r = calcularScoreAnden(
        conteos: const {'Verde': 11, 'Quebrada': 11},
        totalFrutos: 100,
      );
      expect(r.puntosTotal, lessThan(kPuntosMinimos));
      expect(r.disposicion, 'RECHAZO');
    });

    test('puntos por defecto: 15 menos la parte entera del porcentaje', () {
      // Verificado contra los reportes oficiales de Driscoll's.
      final r = calcularScoreAnden(
        conteos: const {'Verde': 34}, // 3.4%
        totalFrutos: 1000,
      );
      final verde =
          r.detalle.firstWhere((d) => d.defecto.nombre == 'Verde');
      expect(verde.puntos, 12);
    });

    test('sin frutos capturados no truena ni inventa defectos', () {
      final r = calcularScoreAnden(conteos: const {}, totalFrutos: 0);
      expect(r.pctCondicion, 0);
      expect(r.pctApariencia, 0);
    });
  });

  group('disposicion: llave nueva y llave vieja', () {
    test('esReempaque reconoce las dos', () {
      expect(esReempaque('REEMPAQUE'), isTrue);
      expect(esReempaque('PRE-RECHAZO'), isTrue); // registros v1.2-v1.4
      expect(esReempaque('PASO'), isFalse);
      expect(esReempaque('RECHAZO'), isFalse);
    });

    test('un registro viejo se muestra y se pinta como reempaque', () {
      expect(etiquetaDisposicion(kDispReempaqueLegado), 'REEMPAQUE');
      expect(nivelDisposicion(kDispReempaqueLegado), 'warn');
      expect(nivelDisposicion('PASO'), 'ok');
      expect(nivelDisposicion('RECHAZO'), 'danger');
    });
  });

  group('calcularProceso (potencial empacable v1.5)', () {
    test('es la suma de los cuatro recuperables, no el complemento', () {
      final r = calcularProceso(const {
        'Verde': 10.0,
        'Quebrada': 5.0,
        'Suciedad': 20.0, // no es recuperable
      });
      expect(r.potencialEmpacable, 15.0);
      expect(r.totalDefectos, 35.0);
      // Con la regla de v1.4 esto habria dado 65.0.
      expect(r.potencialEmpacable, isNot(100 - r.totalDefectos));
    });

    test('los cuatro defectos de la lista suman', () {
      final r = calcularProceso({
        for (final llave in kDefectosPotencialEmpacable) llave: 2.5,
      });
      expect(r.potencialEmpacable, closeTo(10.0, 0.001));
    });

    test('las llaves de la lista existen en el catalogo de proceso', () {
      // Si alguien renombra un defecto en constants.dart sin actualizar
      // la lista, el potencial empacable se iria a cero en silencio.
      for (final llave in kDefectosPotencialEmpacable) {
        expect(
          kDefectosProceso.any((d) => d.nombre == llave),
          isTrue,
          reason: 'La llave "$llave" ya no existe en kDefectosProceso',
        );
      }
    });

    test('sin defectos el potencial empacable es cero', () {
      final r = calcularProceso(const {});
      expect(r.potencialEmpacable, 0);
      expect(r.totalDefectos, 0);
    });

    test('el % por area se sigue calculando', () {
      final r = calcularProceso(const {'Fumagina': 10.0}); // Agronomia
      expect(r.porArea['Agronomia'], 10.0);
      expect(r.porArea['Cosecha'], 0.0);
    });

    test('el semaforo va al reves que en v1.4', () {
      expect(nivelPotencialEmpacable(10.0), 'ok');
      expect(nivelPotencialEmpacable(15.0), 'warn');
      expect(nivelPotencialEmpacable(20.0), 'danger');
      expect(nivelPotencialEmpacable(25.0), 'danger');
    });
  });

  group('calcularPctProceso', () {
    test('kilos y porcentaje segun la hoja de la clienta', () {
      final r = calcularPctProceso(cajas: 100, taras: 2);
      expect(r.kgCajas, closeTo(223.0, 0.01));
      expect(r.kgTaras, closeTo(5.2, 0.01));
      expect(r.pct, closeTo(2.28, 0.01));
      expect(r.excede, isFalse);
    });

    test('arriba de 8% enciende el rojo', () {
      final r = calcularPctProceso(cajas: 10, taras: 10);
      expect(r.excede, isTrue);
    });

    test('sin capturar nada el porcentaje es nulo', () {
      expect(calcularPctProceso(cajas: 0, taras: 0).pct, isNull);
    });
  });
}
