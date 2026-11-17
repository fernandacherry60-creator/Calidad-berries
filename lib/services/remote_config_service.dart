import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Configuración remota, no ejecuta código descargado.
/// Los cambios se reflejan sin publicar una APK nueva.
class RemoteConfigService extends ChangeNotifier {
  Map<String, dynamic> features = const {
    'enable_sampling': true,
    'enable_semaforo': true,
    'enable_cloud_sync': true,
  };
  Map<String, dynamic> release = const {
    'minimum_version': '1.6.0',
    'recommended_version': '1.6.0',
    'maintenance': false,
    'message': '',
  };
  Timer? _timer;

  Future<void> init() async {
    await refresh();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => refresh());
  }

  Future<void> refresh() async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    try {
      final rows = await Supabase.instance.client
          .from('cb_app_config').select('key,value');
      for (final row in rows) {
        final value = Map<String, dynamic>.from(row['value'] as Map);
        if (row['key'] == 'features') features = value;
        if (row['key'] == 'release') release = value;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Configuración remota no disponible: $e');
    }
  }

  bool enabled(String feature) => features[feature] == true;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
