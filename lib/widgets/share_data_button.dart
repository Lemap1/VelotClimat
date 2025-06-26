import 'package:flutter/material.dart';
import 'package:sensor_logging/utils.dart';
import 'package:share_plus/share_plus.dart';

/// A button widget that allows the user to share all locally stored CSV data files as a ZIP archive.
class ShareDataButton extends StatelessWidget {
  const ShareDataButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () async {
          try {
            // Attempt to zip all CSV files in the app's storage directory
            final zipFile = await Utils.zipAllCsv();
            if (zipFile != null) {
              // If a ZIP file was created, open the system share dialog
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
