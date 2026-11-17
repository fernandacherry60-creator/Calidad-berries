import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/sync_service.dart';

/// Campo numerico grande con botones +/- : capturar con una mano y con
/// guantes, sin pelearse con el teclado.
class ContadorDefecto extends StatelessWidget {
  final String label;
  final int valor;
  final ValueChanged<int> onChanged;
  final Color? acento;

  const ContadorDefecto({
    super.key,
    required this.label,
    required this.valor,
    required this.onChanged,
    this.acento,
  });

  @override
  Widget build(BuildContext context) {
    final activo = valor > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: activo ? (acento ?? AppColors.warnBg) : AppColors.card,
        border: Border.all(
            color: activo ? AppColors.warn : AppColors.line,
            width: activo ? 1.5 : 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: activo ? FontWeight.w700 : FontWeight.w500)),
          ),
          _Boton(
            icono: Icons.remove,
            onTap: valor > 0 ? () => onChanged(valor - 1) : null,
          ),
          SizedBox(
            width: 56,
            child: TextFormField(
              key: ValueKey('$label-$valor'),
              initialValue: '$valor',
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false),
              onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
            ),
          ),
          _Boton(icono: Icons.add, onTap: () => onChanged(valor + 1)),
        ],
      ),
    );
  }
}

class _Boton extends StatelessWidget {
  final IconData icono;
  final VoidCallback? onTap;
  const _Boton({required this.icono, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Icon(icono,
              size: 24,
              color: onTap == null ? AppColors.line : AppColors.primary),
        ),
      ),
    );
  }
}

/// Chip semaforizado para scores y disposiciones.
class ChipSemaforo extends StatelessWidget {
  final String texto;
  final String nivel; // 'ok' | 'warn' | 'danger'
  final double? tamano;
  const ChipSemaforo(
      {super.key, required this.texto, required this.nivel, this.tamano});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (nivel) {
      'ok' => (AppColors.okBg, AppColors.ok),
      'warn' => (AppColors.warnBg, AppColors.warn),
      _ => (AppColors.dangerBg, AppColors.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(texto,
          style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: tamano ?? 14)),
    );
  }
}

/// Banner permanente de estado de conexion + pendientes de sincronizar.
/// El inspector siempre sabe si esta trabajando offline y cuantos registros
/// esperan subir. Nunca bloquea el trabajo.
class BannerConexion extends StatelessWidget {
  const BannerConexion({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final texto = sync.conectado
        ? (sync.pendientes > 0
            ? 'En linea - subiendo ${sync.pendientes} pendiente(s)'
            : 'En linea - todo sincronizado')
        : (sync.pendientes > 0
            ? 'Sin conexion - ${sync.pendientes} guardado(s) en el equipo'
            : 'Sin conexion - se guardara en el equipo');
    final color = sync.conectado ? AppColors.ok : AppColors.warn;
    final bg = sync.conectado ? AppColors.okBg : AppColors.warnBg;
    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(sync.conectado ? Icons.cloud_done : Icons.cloud_off,
              size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class TituloSeccion extends StatelessWidget {
  final String texto;
  const TituloSeccion(this.texto, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Text(texto.toUpperCase(),
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: AppColors.inkSoft)),
    );
  }
}
