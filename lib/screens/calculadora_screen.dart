import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/scoring.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// Calculadora de defectos (v1.3, pedido de la clienta).
///
/// Reemplaza a su antigua "calculadora" de Excel: se capturan frutos
/// totales y conteos de defectos, y la app muestra en vivo los
/// porcentajes, puntos y la disposicion (PASO / REEMPAQUE / RECHAZO)
/// con el mismo motor Driscoll's del muestreo real (v1.4: reempaque en
/// v1.5: reempaque de 15% a 15.5% de apariencia, rechazo desde
/// 15.6%).
///
/// NO guarda nada, no sincroniza nada y no toca el historial: es una
/// herramienta de simulacion, capacitacion y verificacion rapida.
class CalculadoraScreen extends StatefulWidget {
  const CalculadoraScreen({super.key});

  @override
  State<CalculadoraScreen> createState() => _CalculadoraScreenState();
}

class _CalculadoraScreenState extends State<CalculadoraScreen> {
  final Map<String, int> _conteos = {};
  final _frutos = TextEditingController(text: '100');
  final _larva = TextEditingController(text: '0');

  int get _totalFrutos => int.tryParse(_frutos.text) ?? 0;
  int get _frutosLarva => int.tryParse(_larva.text) ?? 0;

  ResultadoScore get _resultado => calcularScoreAnden(
        conteos: _conteos,
        totalFrutos: _totalFrutos,
        frutosLarva: _frutosLarva,
      );

  void _limpiar() {
    setState(() {
      _conteos.clear();
      _frutos.text = '100';
      _larva.text = '0';
    });
  }

  @override
  void dispose() {
    _frutos.dispose();
    _larva.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = _resultado;
    final condicion = r.detalle
        .where((d) => d.defecto.categoria == 'condicion')
        .toList();
    final apariencia = r.detalle
        .where((d) => d.defecto.categoria == 'apariencia')
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calculadora de defectos'),
        actions: [
          IconButton(
            tooltip: 'Limpiar todo',
            icon: const Icon(Icons.refresh),
            onPressed: _limpiar,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.warnBg,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Text(
              'Modo simulación: aquí no se guarda ningún registro',
              style: TextStyle(
                  color: AppColors.warn,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              children: [
                const TituloSeccion('Muestra'),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _frutos,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: const InputDecoration(
                            labelText: 'Frutos totales'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _larva,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: const InputDecoration(
                            labelText: 'Frutos con larva'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                _Categoria(
                  titulo: 'Condición (rechazo si suma > 5%)',
                  resultados: condicion,
                  conteos: _conteos,
                  onChanged: (n, v) => setState(() => _conteos[n] = v),
                ),
                _Categoria(
                  titulo:
                      'Apariencia (reempaque en 15%, rechazo arriba de 15%)',
                  resultados: apariencia,
                  conteos: _conteos,
                  onChanged: (n, v) => setState(() => _conteos[n] = v),
                ),
                const SizedBox(height: 90),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: AppColors.card,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              ChipSemaforo(
                  texto: etiquetaDisposicion(r.disposicion),
                  nivel: nivelDisposicion(r.disposicion),
                  tamano: 15),
              const SizedBox(width: 10),
              Text('${r.puntosTotal}/$kPuntosTotales',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  r.motivo.isNotEmpty
                      ? r.motivo
                      : 'Cond ${(r.pctCondicion * 100).toStringAsFixed(1)}% - Apar ${(r.pctApariencia * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Categoria extends StatelessWidget {
  final String titulo;
  final List<ResultadoDefecto> resultados;
  final Map<String, int> conteos;
  final void Function(String nombre, int valor) onChanged;
  const _Categoria({
    required this.titulo,
    required this.resultados,
    required this.conteos,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TituloSeccion(titulo),
        for (final r in resultados)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ContadorDefecto(
                  label: r.defecto.tolerancia != null
                      ? '${r.defecto.etiqueta} (${(r.defecto.tolerancia! * 100).toStringAsFixed(1)}%)'
                      : r.defecto.etiqueta,
                  valor: conteos[r.defecto.nombre] ?? 0,
                  onChanged: (v) => onChanged(r.defecto.nombre, v),
                ),
                if ((conteos[r.defecto.nombre] ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 3),
                    child: Text(
                      '${(r.pct * 100).toStringAsFixed(1)}%'
                      '${r.defecto.puntosMax > 0 ? ' - ${r.puntos} pts' : ''}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkSoft),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
