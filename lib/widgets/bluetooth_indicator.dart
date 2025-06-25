import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothIndicator extends StatelessWidget {
  final BluetoothAdapterState bluetoothAdapterState;
  const BluetoothIndicator({super.key, required this.bluetoothAdapterState});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
