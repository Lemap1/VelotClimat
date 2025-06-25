import 'package:flutter/material.dart';

class LiveStatusCard extends StatelessWidget {
  final String connectionStatus; // Example status
  final String? temperature; // Example temperature data
  final String? humidity; // Example humidity data
  final String? latitude; // Example latitude data
  final String? longitude; // Example longitude data

  const LiveStatusCard({
    super.key,
    required this.connectionStatus,
    required this.temperature,
    required this.humidity,
    required this.latitude,
    required this.longitude,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusRow(
              'État du service :',
              connectionStatus,
              icon: Icons.info,
              iconColor: Colors.blue.shade700,
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildBigData(
                  icon: Icons.thermostat,
                  label: 'Temp',
                  value: temperature ?? '--',
                  color: Colors.orange.shade700,
                ),
                _buildBigData(
                  icon: Icons.water_drop,
                  label: 'Hum',
                  value: humidity ?? '--',
                  color: Colors.blue.shade700,
                ),
                _buildBigData(
                  icon: Icons.north, // Different icon for latitude
                  label: 'Lat',
                  value: latitude ?? '--',
                  color: Colors.green.shade700,
                ),
                _buildBigData(
                  icon: Icons.east, // Different icon for longitude
                  label: 'Lon',
                  value: longitude ?? '--',
                  color: Colors.green.shade700,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Helper widget to build a consistent status row (Label: Value).
  Widget _buildStatusRow(
    String label,
    String value, {
    IconData? icon,
    Color? iconColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 8.0, top: 2.0),
            child: Icon(icon, size: 22),
          ),
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 15))),
      ],
    );
  }

  /// Helper widget to display a large data value with an icon.
  Widget _buildBigData({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
