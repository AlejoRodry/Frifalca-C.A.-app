import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:convert';
import 'dart:ui';
import 'theme.dart';

class UpdateService {
  // Lista de URLs para buscar actualizaciones (Redundancia)
  static const List<String> _versionUrls = [
    "https://frifalca-db.web.app/version.json", // Prioridad: Firebase Hosting
    "https://raw.githubusercontent.com/AlejoRodry/Frifalca-C.A.-app/main/version.json", // Respaldo: GitHub
  ];

  static Future<void> checkUpdate(BuildContext context) async {
    final dio = Dio();
    final packageInfo = await PackageInfo.fromPlatform();
    final String currentVersion = packageInfo.version;

    for (String url in _versionUrls) {
      try {
        final response = await dio
            .get(url)
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          Map<String, dynamic> data;
          if (response.data is String) {
            data = jsonDecode(response.data);
          } else {
            data = response.data;
          }

          if (data.containsKey('version_code') &&
              data.containsKey('url_descarga')) {
            final String remoteVersion = data['version_code'];
            final String downloadUrl = data['url_descarga'];

            if (_isNewerVersion(remoteVersion, currentVersion)) {
              if (context.mounted) {
                _showUpdateDialog(context, remoteVersion, downloadUrl);
              }
              return;
            }
          }
          return;
        }
      } catch (e) {
        debugPrint("Error al verificar actualización en $url: $e");
        // Continuar con la siguiente URL si esta falló
      }
    }
  }

  static bool _isNewerVersion(String remote, String current) {
    // Compara versiones tipo 1.0.0. Puedes usar package_info_plus buildNumber si prefieres.
    List<int> remoteParts = remote.split('.').map(int.parse).toList();
    List<int> currentParts = current.split('.').map(int.parse).toList();

    for (int i = 0; i < remoteParts.length; i++) {
      if (i >= currentParts.length) return true;
      if (remoteParts[i] > currentParts[i]) return true;
      if (remoteParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  static void _showUpdateDialog(
    BuildContext context,
    String version,
    String url,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _UpdateDialog(version: version, downloadUrl: url),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final String version;
  final String downloadUrl;

  const _UpdateDialog({required this.version, required this.downloadUrl});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double _progress = 0;
  bool _isDownloading = false;
  String _statusText = "Nueva versión disponible";

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _statusText = "Descargando actualización...";
    });

    try {
      final dio = Dio();
      final tempDir = await getTemporaryDirectory();
      final String savePath = "${tempDir.path}/app_update.apk";

      await dio.download(
        widget.downloadUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _progress = received / total;
            });
          }
        },
      );

      setState(() {
        _statusText = "Descarga completada. Instalando...";
        _progress = 1.0;
      });

      await OpenFilex.open(savePath);
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _statusText = "Error en la descarga. Intenta de nuevo.";
      });
      debugPrint("Error de descarga: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: AlertDialog(
        backgroundColor: Colors.white.withAlpha(20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withAlpha(50)),
        ),
        title: Text(
          "Actualización Disponible",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Versión: ${widget.version}",
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            Text(
              _statusText,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            if (_isDownloading) ...[
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.secondary,
                  ),
                  minHeight: 10,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "${(_progress * 100).toStringAsFixed(0)}%",
                style: const TextStyle(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!_isDownloading)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Más tarde",
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ElevatedButton(
            onPressed: _isDownloading ? null : _startDownload,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(_isDownloading ? "Descargando..." : "Actualizar Ahora"),
          ),
        ],
      ),
    );
  }
}
