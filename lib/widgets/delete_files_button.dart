import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensor_logging/utils.dart';

/// A button widget that allows the user to delete all locally stored CSV data files.
///
/// This widget displays an outlined button with a delete icon. When pressed,
/// it shows a confirmation dialog to the user. If the user confirms, all CSV files
/// in the app's storage directory are deleted. The button can be disabled (for example,
/// when a sensor is connected) to prevent accidental deletion during critical operations.
class DeleteFilesButton extends StatelessWidget {
  /// If true, the button is disabled and cannot be pressed.
  final bool isDisabled;

  const DeleteFilesButton({super.key, this.isDisabled = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () {
          // If the button is disabled, show a message and do nothing else.
          isDisabled
              ? Utils.showSnackBar(
                  "Suppression impossible lorsqu’un capteur est connecté.",
                  context,
                )
              : showDialog<void>(
                  context: context,
                  barrierDismissible: true,
                  builder: (BuildContext context) {
                    // Confirmation dialog before deleting files
                    return AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      backgroundColor: Colors.white,
                      title: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.delete_forever,
                            color: Colors.red.shade700,
                            size: 28,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Supprimer les données',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                color: Colors.black87,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      content: const Text(
                        'Êtes-vous sûr de vouloir supprimer toutes les données ? Cette action est irréversible.',
                        style: TextStyle(fontSize: 16, color: Colors.black87),
                      ),
                      actionsPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      actions: <Widget>[
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue.shade700,
                            side: BorderSide(color: Colors.blue.shade200),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                          ),
                          child: const Text(
                            'Annuler',
                            style: TextStyle(fontSize: 16),
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            elevation: 2,
                          ),
                          icon: const Icon(Icons.delete, size: 20),
                          label: const Text(
                            'Supprimer',
                            style: TextStyle(fontSize: 16),
                          ),
                          onPressed: () {
                            // Perform the deletion of all files
                            deleteAllFiles(context);

                            Navigator.of(context).pop();
                          },
                        ),
                      ],
                    );
                  },
                );
        },
        icon: const Icon(Icons.delete, color: Colors.redAccent),
        label: const Text(
          'Supprimer',
          style: TextStyle(fontSize: 15, color: Colors.redAccent),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: const BorderSide(color: Colors.redAccent),
        ),
      ),
    );
  }

  /// Deletes all CSV and ZIP files in the app's storage directory.
  Future<void> deleteAllFiles(BuildContext context) async {
    List<File> allCsvFiles = await Utils.getAllCsvFiles();
    // Use archive plugin to zip all csv files (not used here, just a comment)
    if (allCsvFiles.isEmpty) {
      Utils.showSnackBar('Aucune donnée à supprimer', context);
      return;
    } else {
      Utils.showSnackBar('Suppression des données en cours', context);
      for (var file in allCsvFiles) {
        try {
          await file.delete();
        } catch (e) {
          // Notify the user if a file could not be deleted
          Utils.showSnackBar(
            'Erreur lors de la suppression du fichier ${file.path}: $e',
            context,
          );
        }
      }

      // Also delete the zip file if it exists
      Directory? directory;
      if (Platform.isAndroid) {
        directory = await getExternalStorageDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
      if (directory == null) {
        throw Exception("Could not get application directory for CSV storage.");
      }

      if (File('${directory.path}/sensor_data.zip').existsSync()) {
        await File('${directory.path}/sensor_data.zip').delete();
      }
      Utils.showSnackBar('Données supprimées', context);
    }
  }
}
