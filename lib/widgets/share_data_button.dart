import 'package:flutter/material.dart';
import 'package:sensor_logging/utils.dart';
import 'package:share_plus/share_plus.dart';

class ShareDataButton extends StatelessWidget {
  const ShareDataButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () async {
          try {
            final zipFile = await Utils.zipAllCsv();
            if (zipFile != null) {
              await SharePlus.instance.share(
                ShareParams(files: [XFile(zipFile.path)]),
              );
            } else {
              Utils.showSnackBar('Aucune donnée à partager', context);
            }
          } catch (e) {
            Utils.showSnackBar('Erreur partage : $e', context);
          }
        },
        icon: const Icon(Icons.share, color: Colors.blueAccent),
        label: const Text(
          'Partager',
          style: TextStyle(fontSize: 15, color: Colors.blueAccent),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: const BorderSide(color: Colors.blueAccent),
        ),
      ),
    );
  }
}
