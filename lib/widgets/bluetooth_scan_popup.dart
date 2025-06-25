import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothScanPopup extends StatefulWidget {
  final bool isRunning;

  final Function(BluetoothDevice device) onDeviceSelected;

  const BluetoothScanPopup({
    super.key,
    required this.onDeviceSelected,
    required this.isRunning,
  });

  @override
  State<BluetoothScanPopup> createState() => _BluetoothScanPopupState();
}

class _BluetoothScanPopupState extends State<BluetoothScanPopup> {
  BluetoothDevice? _connectedDevice;

  void _showScanDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _BluetoothScanDialog(
        onDeviceSelected: (device) {
          setState(() {
            _connectedDevice = device;
          });
          widget.onDeviceSelected(device);
        },
        connectedDevice: _connectedDevice,
        isRunning: widget.isRunning,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      onPressed: () => _showScanDialog(context),
      icon: const Icon(Icons.bluetooth_searching),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _BluetoothScanDialog extends StatefulWidget {
  final Function(BluetoothDevice device) onDeviceSelected;
  final BluetoothDevice? connectedDevice;
  final bool isRunning;

  const _BluetoothScanDialog({
    required this.onDeviceSelected,
    required this.connectedDevice,
    required this.isRunning,
  });

  @override
  State<_BluetoothScanDialog> createState() => _BluetoothScanDialogState();
}

class _BluetoothScanDialogState extends State<_BluetoothScanDialog> {
  List<BluetoothDevice> _devices = [];
  bool _isScanning = true;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  Timer? _scanTimeout;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    _scanTimeout?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _devices = [];
      _isScanning = true;
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));

    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _devices = results.map((r) => r.device).toSet().toList();
        if (widget.connectedDevice != null &&
            !_devices.contains(widget.connectedDevice) &&
            widget.isRunning) {
          _devices.add(widget.connectedDevice!);
        }
      });
    });

    _scanTimeout?.cancel();
    _scanTimeout = Timer(const Duration(seconds: 4), () {
      FlutterBluePlus.stopScan();
      setState(() {
        _isScanning = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.bluetooth_searching, color: Colors.blue),
          const SizedBox(width: 8),
          const Text(
            'Capteurs trouvés',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.only(left: 8.0),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _isScanning && _devices.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(),
                ),
              )
            : _devices.isEmpty
            ? const Center(
                child: Text(
                  'Aucun appareil trouvé',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : SingleChildScrollView(
                child: ListView.separated(
                  shrinkWrap: true,

                  itemCount: _devices.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    final isConnected =
                        widget.connectedDevice != null &&
                        (device.id == widget.connectedDevice!.id) &&
                        widget.isRunning;
                    return ListTile(
                      leading: const Icon(Icons.bluetooth),
                      title: Text(
                        device.name.isNotEmpty
                            ? device.name
                            : device.id.toString(),
                      ),
                      subtitle: Text(device.id.toString()),
                      trailing: isConnected
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null,
                      onTap: () {
                        widget.onDeviceSelected(device);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
      ),
      actions: [
        TextButton(
          child: const Text('Rafraîchir'),
          onPressed: _isScanning
              ? null
              : () {
                  _startScan();
                },
        ),
        TextButton(
          child: const Text('Terminé'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
