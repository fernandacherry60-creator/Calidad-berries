import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../../widgets/common.dart';
import 'anden_defects_screen.dart';

/// Paso 1 del muestreo de anden: identificacion de la tarima.
/// Estructura oficial del cliente: Rancho (catalogo), Sector (manual),
/// Variedad y Presentacion (catalogo), Cuadrilla (manual).
/// v1.3: la Licencia se captura al final de la pantalla de defectos
/// (pedido de la clienta).
class AndenFormScreen extends StatefulWidget {
  final String cultivo;
  const AndenFormScreen({super.key, required this.cultivo});

  @override
  State<AndenFormScreen> createState() => _AndenFormScreenState();
}

class _AndenFormScreenState extends State<AndenFormScreen> {
  final _repo = CatalogoRepo();
  final _form = GlobalKey<FormState>();

  List<String> _ranchos = [];
  List<String> _variedades = [];

  String? _rancho;
  String? _variedad;
  String? _presentacion;
  final _sector = TextEditingController();
  final _cuadrilla = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final ranchos = await _repo.ranchos();
    final variedades = await _repo.variedades(widget.cultivo);
    if (!mounted) return;
    setState(() {
      _ranchos = ranchos;
      _variedades = variedades;
    });
  }

  void _continuar() {
    if (!_form.currentState!.validate()) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AndenDefectsScreen(
          cultivo: widget.cultivo,
          rancho: _rancho!,
          sector: _sector.text.trim(),
          variedad: _variedad!,
          presentacion: _presentacion!,
          cuadrilla: _cuadrilla.text.trim(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sector.dispose();
    _cuadrilla.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.cultivo[widget.cultivo] ?? AppColors.primary;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Andenes'),
            const SizedBox(width: 10),
            ChipSemaforo(texto: widget.cultivo, nivel: 'ok', tamano: 13),
          ],
        ),
      ),
      body: Column(
        children: [
          const BannerConexion(),
          Expanded(
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  const TituloSeccion('Origen de la fruta'),
                  DropdownButtonFormField<String>(
                    value: _rancho,
                    decoration: const InputDecoration(labelText: 'Rancho'),
                    items: [
                      for (final r in _ranchos)
                        DropdownMenuItem(value: r, child: Text(r))
                    ],
                    onChanged: (v) => setState(() => _rancho = v),
                    validator: (v) => v == null ? 'Selecciona el rancho' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _sector,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                        labelText: 'Sector',
                        helperText: 'Se escribe manualmente'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Escribe el sector'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: _variedad,
                    decoration: const InputDecoration(labelText: 'Variedad'),
                    items: [
                      for (final v in _variedades)
                        DropdownMenuItem(value: v, child: Text(v))
                    ],
                    onChanged: (v) => setState(() => _variedad = v),
                    validator: (v) =>
                        v == null ? 'Selecciona la variedad' : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: _presentacion,
                    decoration:
                        const InputDecoration(labelText: 'Presentación'),
                    items: [
                      for (final p in kPresentaciones)
                        DropdownMenuItem(
                            value: p.nombre, child: Text(p.nombre))
                    ],
                    onChanged: (v) => setState(() => _presentacion = v),
                    validator: (v) =>
                        v == null ? 'Selecciona la presentacion' : null,
                  ),
                  const TituloSeccion('Recepción'),
                  TextFormField(
                    controller: _cuadrilla,
                    textCapitalization: TextCapitalization.words,
                    decoration:
                        const InputDecoration(labelText: 'Cuadrilla'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Escribe la cuadrilla'
                        : null,
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: color),
                    onPressed: _continuar,
                    child: const Text('Continuar al muestreo'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
