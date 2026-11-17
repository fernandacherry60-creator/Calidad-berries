import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/scoring.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../services/auth_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/common.dart';
import 'anden_resumen_screen.dart';

/// Paso 2: conteo de defectos con calificacion Driscoll's EN VIVO.
/// v1.5: Condicion >5% = RECHAZO; Apariencia 15%-15.5% = REEMPAQUE y
/// 15.6% o mas = RECHAZO (regla de la clienta del 25/ago);
/// larva: 1 fruto = REEMPAQUE, 2+ = RECHAZO; total <60 pts = RECHAZO.
///
/// v1.5 (pedidos de la clienta del 25/ago):
/// - Canastos se autollena redondeando HACIA ARRIBA: 24 cajas = 1,
///   48 = 2, 62 = 3 (editable).
/// - El campo "Muestreados" pasa a ser "Embaladora" (nombre de quien
///   embalo) y aparece en el resumen y en la confirmacion final.
/// - Seccion "Muestreo general" (antes "Inocuidad y mediciones") con
///   los campos en dos filas para que las etiquetas salgan completas.
/// - Evaluador (precargado con el usuario, editable) y Licencia al
///   final de la pantalla.
/// - Dialogo de confirmacion con toda la informacion, sin recortes.
class AndenDefectsScreen extends StatefulWidget {
  final String cultivo;
  final String rancho;
  final String sector;
  final String variedad;
  final String presentacion;
  final String cuadrilla;

  const AndenDefectsScreen({
    super.key,
    required this.cultivo,
    required this.rancho,
    required this.sector,
    required this.variedad,
    required this.presentacion,
    required this.cuadrilla,
  });

  @override
  State<AndenDefectsScreen> createState() => _AndenDefectsScreenState();
}

class _AndenDefectsScreenState extends State<AndenDefectsScreen> {
  final _repo = MuestreoRepo();
  final _picker = ImagePicker();
  final Map<String, int> _conteos = {};
  final List<String> _fotos = [];
  final _cajas = TextEditingController();
  final _canastos = TextEditingController();
  final _frutaMuestra = TextEditingController();
  final _embaladora = TextEditingController();
  final _brix = TextEditingController();
  final _peso = TextEditingController();
  final _larva = TextEditingController(text: '0');
  final _evaluador = TextEditingController();
  final _licencia = TextEditingController();
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    // El evaluador se precarga con quien esta logueado, pero es editable
    // por si otra persona realiza la evaluacion.
    final auth = context.read<AuthService>();
    _evaluador.text = auth.usuario?.displayName ?? '';
  }

  int get _totalFrutos => int.tryParse(_frutaMuestra.text) ?? 0;
  int get _frutosLarva => int.tryParse(_larva.text) ?? 0;
  double? get _pesoCapturado => double.tryParse(_peso.text);
  Presentacion? get _presentacion =>
      presentacionPorNombre(widget.presentacion);

  /// Regla de la clienta (25/ago): 1 canasto muestreado por cada 24
  /// cajas recibidas O FRACCION, es decir redondeando hacia arriba
  /// (24 = 1, 48 = 2, 62 = 3). El campo queda editable por si el
  /// inspector necesita corregirlo a mano.
  void _autoCanastos() {
    final cajas = int.tryParse(_cajas.text) ?? 0;
    if (cajas <= 0) {
      _canastos.text = '';
      return;
    }
    _canastos.text = '${canastosPorCajas(cajas)}';
  }

  /// Verificacion de peso previa a la inspeccion (tabla Grupo Ojo Zarco):
  /// si el peso del clamshell es menor al minimo de su presentacion,
  /// es RECHAZO por bajo peso sin importar los defectos.
  bool get _bajoPeso {
    final pres = _presentacion;
    final peso = _pesoCapturado;
    return pres != null && peso != null && peso > 0 && peso < pres.pesoMinG;
  }

  ResultadoScore get _resultado {
    final r = calcularScoreAnden(
      conteos: _conteos,
      totalFrutos: _totalFrutos,
      frutosLarva: _frutosLarva,
    );
    if (_bajoPeso) {
      return ResultadoScore(
        detalle: r.detalle,
        pctCondicion: r.pctCondicion,
        pctApariencia: r.pctApariencia,
        puntosCondicion: r.puntosCondicion,
        puntosApariencia: r.puntosApariencia,
        puntosTotal: r.puntosTotal,
        disposicion: 'RECHAZO',
        motivo:
            'Bajo peso (${_pesoCapturado!.toStringAsFixed(1)} g, mínimo ${_presentacion!.pesoMinG} g)',
      );
    }
    return r;
  }

  @override
  void dispose() {
    _cajas.dispose();
    _canastos.dispose();
    _frutaMuestra.dispose();
    _embaladora.dispose();
    _brix.dispose();
    _peso.dispose();
    _larva.dispose();
    _evaluador.dispose();
    _licencia.dispose();
    super.dispose();
  }

  Future<void> _agregarFoto(ImageSource origen) async {
    final foto = await _picker.pickImage(
        source: origen, maxWidth: 1600, imageQuality: 80);
    if (foto == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final fotosDir = Directory(p.join(dir.path, 'fotos'));
    if (!fotosDir.existsSync()) fotosDir.createSync(recursive: true);
    final destino = p.join(fotosDir.path,
        'ev_${DateTime.now().millisecondsSinceEpoch}${p.extension(foto.path)}');
    await File(foto.path).copy(destino);
    if (!mounted) return;
    setState(() => _fotos.add(destino));
  }

  void _menuFoto() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () {
                Navigator.pop(ctx);
                _agregarFoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () {
                Navigator.pop(ctx);
                _agregarFoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _aviso(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _guardar() async {
    if (_totalFrutos <= 0) {
      _aviso('Indica los frutos totales inspeccionados');
      return;
    }
    final defectuosos = _conteos.values.fold<int>(0, (a, b) => a + b);
    if (defectuosos > _totalFrutos) {
      _aviso('Los frutos con defecto superan el total inspeccionado');
      return;
    }
    if (_evaluador.text.trim().isEmpty) {
      _aviso('Escribe el nombre del evaluador');
      return;
    }
    if (_licencia.text.trim().isEmpty) {
      _aviso('Escribe la licencia del transportista (al final de la pantalla)');
      return;
    }

    final r = _resultado;

    // v1.4: pantalla resumen tipo tabla (pedido de la clienta: "antes
    // de la ultima pagina de anden necesito esta pagina justo asi").
    // Despues de aceptarla se muestra el dialogo final de siempre.
    final revisado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AndenResumenScreen(
          cultivo: widget.cultivo,
          rancho: widget.rancho,
          sector: widget.sector,
          variedad: widget.variedad,
          presentacion: widget.presentacion,
          cuadrilla: widget.cuadrilla,
          embaladora: _embaladora.text.trim(),
          totalFrutos: _totalFrutos,
          frutosLarva: _frutosLarva,
          resultado: r,
        ),
      ),
    );
    if (revisado != true || !mounted) return;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar muestreo'),
        // Scroll + textos con salto de linea natural: nada se recorta
        // aunque el rancho, la cuadrilla o el motivo sean largos.
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LineaDialogo('Rancho', '${widget.rancho} - Sector ${widget.sector}'),
              _LineaDialogo('Variedad',
                  '${widget.variedad} - ${widget.presentacion}'),
              _LineaDialogo('Cuadrilla', widget.cuadrilla),
              _LineaDialogo('Licencia', _licencia.text.trim()),
              _LineaDialogo('Evaluador', _evaluador.text.trim()),
              if (_embaladora.text.trim().isNotEmpty)
                _LineaDialogo('Embaladora', _embaladora.text.trim()),
              _LineaDialogo('Frutos inspeccionados', '$_totalFrutos'),
              if (_fotos.isNotEmpty)
                _LineaDialogo('Evidencia', '${_fotos.length} foto(s) adjuntas'),
              const SizedBox(height: 12),
              Row(
                children: [
                  ChipSemaforo(
                      texto: etiquetaDisposicion(r.disposicion),
                      nivel: nivelDisposicion(r.disposicion)),
                  const SizedBox(width: 10),
                  Text('${r.puntosTotal} / $kPuntosTotales pts',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
              if (r.motivo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(r.motivo,
                      style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Revisar')),
          FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 20)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _guardando = true);
    final auth = context.read<AuthService>();
    final sync = context.read<SyncService>();
    final ahora = DateTime.now();
    await _repo.guardarAnden(MuestreoAnden(
      uuid: '${auth.usuario!.id}-${ahora.microsecondsSinceEpoch}',
      userId: auth.usuario!.id,
      cultivo: widget.cultivo,
      rancho: widget.rancho,
      sector: widget.sector,
      variedad: widget.variedad,
      presentacion: widget.presentacion,
      cuadrilla: widget.cuadrilla,
      cajasRecibidas: int.tryParse(_cajas.text) ?? 0,
      canastos: int.tryParse(_canastos.text) ?? 0,
      frutaMuestra: _totalFrutos,
      licencia: _licencia.text.trim(),
      gradosBrix: double.tryParse(_brix.text),
      peso: double.tryParse(_peso.text),
      frutosLarva: _frutosLarva,
      evaluador: _evaluador.text.trim(),
      embaladora: _embaladora.text.trim(),
      defectos: Map.of(_conteos)..removeWhere((_, v) => v == 0),
      fotos: List.of(_fotos),
      pctCondicion: r.pctCondicion,
      pctApariencia: r.pctApariencia,
      puntosCondicion: r.puntosCondicion,
      puntosApariencia: r.puntosApariencia,
      puntosTotal: r.puntosTotal,
      disposicion: r.disposicion,
      motivo: r.motivo,
      fecha: ahora,
    ));
    await sync.refrescarPendientes();
    if (sync.conectado) await sync.sincronizar();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(sync.conectado
            ? 'Muestreo guardado y enviado'
            : 'Muestreo guardado en el equipo (sin conexión)')));
    Navigator.popUntil(context, (route) => route.isFirst);
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
      appBar: AppBar(title: Text('Muestreo - ${widget.cultivo}')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              children: [
                const TituloSeccion('Muestra'),
                // Dos campos por fila: las etiquetas se leen completas
                // en cualquier telefono (pedido de la clienta).
                Row(
                  children: [
                    Expanded(
                        child: _Num(
                            c: _cajas,
                            label: 'Cajas recibidas',
                            onChanged: () =>
                                setState(_autoCanastos))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _Num(
                            c: _canastos,
                            label: 'Canastos',
                            helper: '1 por cada $kCajasPorCanasto cajas o fracción')),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        child: _Num(
                            c: _frutaMuestra,
                            label: 'Frutos totales',
                            onChanged: () => setState(() {}))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TextFormField(
                      controller: _embaladora,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          labelText: 'Embaladora',
                          helperText: 'Nombre de quien embaló'),
                    )),
                  ],
                ),
                _Categoria(
                  titulo: 'Condición (rechazo si suma > 5%)',
                  resultados: condicion,
                  conteos: _conteos,
                  onChanged: (n, v) => setState(() => _conteos[n] = v),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _ResumenCategoria(
                    etiqueta: 'Suma condición',
                    pct: r.pctCondicion,
                    limite: kUmbralCondicion,
                    puntos: '${r.puntosCondicion} pts',
                  ),
                ),
                _Categoria(
                  titulo: 'Apariencia (reempaque 15% a 15.5%, '
                      'rechazo desde 15.6%)',
                  resultados: apariencia,
                  conteos: _conteos,
                  onChanged: (n, v) => setState(() => _conteos[n] = v),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _ResumenCategoria(
                    etiqueta: 'Suma apariencia',
                    pct: r.pctApariencia,
                    limite: kUmbralAparReempaque,
                    puntos: '${r.puntosApariencia} pts',
                    // Ambar dentro de la banda de reempaque, rojo desde
                    // 15.6%: el inspector ve el estado real, no solo
                    // "pasa / no pasa".
                    nivel: switch (veredictoApariencia(r.pctApariencia)) {
                      'RECHAZO' => 'danger',
                      'REEMPAQUE' => 'warn',
                      _ => 'ok',
                    },
                  ),
                ),
                const TituloSeccion('Muestreo general'),
                Row(
                  children: [
                    Expanded(
                        child: _Num(
                            c: _larva,
                            label: 'Frutos con larva',
                            onChanged: () => setState(() {}))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _Num(
                            c: _brix, label: 'Grados Brix', decimales: true)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: _Num(
                            c: _peso,
                            label: 'Peso (g)',
                            decimales: true,
                            onChanged: () => setState(() {}))),
                    const SizedBox(width: 10),
                    const Expanded(child: SizedBox()),
                  ],
                ),
                if (_presentacion != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _bajoPeso
                          ? 'BAJO PESO: mínimo ${_presentacion!.pesoMinG} g para ${_presentacion!.nombre} - RECHAZO'
                          : 'Rango de peso ${_presentacion!.nombre}: ${_presentacion!.pesoMinG}-${_presentacion!.pesoMaxG} g',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color:
                            _bajoPeso ? AppColors.danger : AppColors.inkSoft,
                      ),
                    ),
                  ),
                if (_frutosLarva > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _frutosLarva == 1
                          ? 'Larva en 1 fruto: REEMPAQUE'
                          : 'Larva en $_frutosLarva frutos: RECHAZO automático',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _frutosLarva == 1
                            ? AppColors.warn
                            : AppColors.danger,
                      ),
                    ),
                  ),
                const TituloSeccion('Evidencia'),
                if (_fotos.isNotEmpty)
                  SizedBox(
                    height: 92,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _fotos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(File(_fotos[i]),
                                width: 92, height: 92, fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: InkWell(
                              onTap: () => setState(() {
                                File(_fotos[i]).delete().ignore();
                                _fotos.removeAt(i);
                              }),
                              child: Container(
                                decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(Icons.close,
                                    size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _menuFoto,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Agregar foto'),
                ),
                // v1.3: cierre del muestreo al final de la pantalla,
                // como lo pidio la clienta.
                const TituloSeccion('Cierre del muestreo'),
                TextFormField(
                  controller: _evaluador,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Evaluador',
                      helperText:
                          'Se precarga con tu usuario; puedes corregirlo'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _licencia,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                      labelText: 'Licencia',
                      helperText: 'Número de licencia del transportista'),
                ),
                const SizedBox(height: 100),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        ChipSemaforo(
                            texto: etiquetaDisposicion(r.disposicion),
                            nivel: nivelDisposicion(r.disposicion),
                            tamano: 15),
                        const SizedBox(width: 10),
                        Text('${r.puntosTotal}/$kPuntosTotales',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      r.motivo.isNotEmpty
                          ? r.motivo
                          : 'Cond ${(r.pctCondicion * 100).toStringAsFixed(1)}% - Apar ${(r.pctApariencia * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 140,
                child: ElevatedButton(
                  onPressed: _guardando ? null : _guardar,
                  child: _guardando
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                      : const Text('Guardar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Linea "Etiqueta: valor" del dialogo de confirmacion. El valor hace
/// salto de linea natural: nunca se recorta con "...".
class _LineaDialogo extends StatelessWidget {
  final String etiqueta;
  final String valor;
  const _LineaDialogo(this.etiqueta, this.valor);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
                text: '$etiqueta: ',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
            TextSpan(text: valor),
          ],
        ),
        softWrap: true,
      ),
    );
  }
}

class _ResumenCategoria extends StatelessWidget {
  final String etiqueta;
  final double pct;
  final double limite;
  final String puntos;

  /// 'ok' | 'warn' | 'danger'. Si no se indica, se deduce del limite.
  final String? nivel;
  const _ResumenCategoria({
    required this.etiqueta,
    required this.pct,
    required this.limite,
    required this.puntos,
    this.nivel,
  });

  @override
  Widget build(BuildContext context) {
    final n = nivel ?? (pct > limite ? 'danger' : 'ok');
    final (color, fondo) = switch (n) {
      'ok' => (AppColors.ok, AppColors.okBg),
      'warn' => (AppColors.warn, AppColors.warnBg),
      _ => (AppColors.danger, AppColors.dangerBg),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$etiqueta: ${(pct * 100).toStringAsFixed(1)}% / ${(limite * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: color),
            ),
          ),
          Text(puntos,
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _Num extends StatelessWidget {
  final TextEditingController c;
  final String label;
  final String? helper;
  final bool decimales;
  final VoidCallback? onChanged;
  const _Num(
      {required this.c,
      required this.label,
      this.helper,
      this.decimales = false,
      this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: c,
      keyboardType: TextInputType.numberWithOptions(decimal: decimales),
      inputFormatters: [
        if (!decimales) FilteringTextInputFormatter.digitsOnly
        else FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
      ],
      decoration: InputDecoration(labelText: label, helperText: helper),
      onChanged: (_) => onChanged?.call(),
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
        for (final r in resultados) ...[
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
      ],
    );
  }
}
