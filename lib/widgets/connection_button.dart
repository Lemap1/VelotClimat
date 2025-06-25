import 'package:flutter/material.dart';

class ConnectionButton extends StatelessWidget {
  final bool isConnecting;
  final bool isServiceRunning;
  final VoidCallback? startLogging;
  final VoidCallback? stopLogging;
  final VoidCallback? onServiceStatusChanged;

  const ConnectionButton({
    super.key,
    required this.isConnecting,
    required this.isServiceRunning,
    required this.startLogging,
    required this.stopLogging,
    required this.onServiceStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: isConnecting
          ? null
          : (isServiceRunning ? stopLogging : startLogging),

      icon: isConnecting
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            )
          : Icon(isServiceRunning ? Icons.stop : Icons.play_arrow),
      label: Text(
        isConnecting
            ? 'Recherche du capteur...'
            : (isServiceRunning ? 'Arrêter' : 'Démarrer'),
        style: const TextStyle(fontSize: 18),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: isServiceRunning
            ? Colors.red.shade700
            : Colors.green.shade700, // Red for stop, Green for start
        foregroundColor: Colors.white, // White text color
        padding: const EdgeInsets.symmetric(
          vertical: 15,
        ), // Larger padding for better touch target
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10), // Rounded button corners
        ),
        elevation: 5, // Add shadow for a raised effect
      ),
    );
  }
}
