import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// A simple widget that visually indicates the current Bluetooth adapter state.
///
/// Displays a Bluetooth icon and a label showing the current state (e.g., ON, OFF).
/// The icon and text color change depending on whether Bluetooth is enabled or not.
class BluetoothIndicator extends StatelessWidget {
  /// The current state of the Bluetooth adapter.
  final BluetoothAdapterState bluetoothAdapterState;

  const BluetoothIndicator({super.key, required this.bluetoothAdapterState});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Icon changes depending on Bluetooth state
        Icon(
          bluetoothAdapterState == BluetoothAdapterState.on
              ? Icons
                    .bluetooth_connected // Icon for Bluetooth ON
              : Icons.bluetooth_disabled, // Icon for Bluetooth OFF
          color: bluetoothAdapterState == BluetoothAdapterState.on
              ? Colors
                    .blue
                    .shade700 // Blue for ON
              : Colors.grey.shade600, // Grey for OFF
          size: 28,
        ),
        const SizedBox(width: 8),
        // Text label showing the Bluetooth state in uppercase
        Text(
          'Bluetooth : ${bluetoothAdapterState.name.toUpperCase()}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: bluetoothAdapterState == BluetoothAdapterState.on
                ? Colors.blue.shade700
                : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
