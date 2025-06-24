import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sensor_logging/utils.dart';

class DeleteFilesButton extends StatelessWidget {
  final bool isDisabled;
  const DeleteFilesButton({super.key, this.isDisabled = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () {
          isDisabled
              ? Utils.showSnackBar(
                  "Suppression impossible lorsqu’un capteur est connecté.",
                  context,
                )
              : showDialog<void>(
                  context: context,
                  barrierDismissible:
                      true, // <-- Allow closing when tapping outside
                  builder: (BuildContext context) {
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

  Future<void> deleteAllFiles(BuildContext context) async {
    List<File> allCsvFiles = await Utils.getAllCsvFiles();
    //use archive plugin to zip all csv files
    if (allCsvFiles.isEmpty) {
      Utils.showSnackBar('Aucune donnée à supprimer', context);
      return;
    } else {
      Utils.showSnackBar('Suppression des données en cours', context);
      for (var file in allCsvFiles) {
        try {
          await file.delete();
        } catch (e) {
          Utils.showSnackBar(
            'Erreur lors de la suppression du fichier ${file.path}: $e',
            context,
          );
        }
      }
      Utils.showSnackBar('Données supprimées', context);
    }
  }
}
