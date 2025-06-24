// --- UI (Page) ---
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensor_logging/widgets/delete_files_button.dart';
import 'package:sensor_logging/utils.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:sensor_logging/widgets/share_data_button.dart';

class BluetoothConnectorPage extends StatefulWidget {
  const BluetoothConnectorPage({super.key});

  @override
  State<BluetoothConnectorPage> createState() => _BluetoothConnectorPageState();
}

class _BluetoothConnectorPageState extends State<BluetoothConnectorPage> {
  // Controller for the Bluetooth device name input field
  final TextEditingController _deviceNameController = TextEditingController(
    text: "",
  );
  bool disableDeleteButton = false;

  // UI state variables to display real-time logging information
  String _connectionStatus = 'Service Stopped';
  String _characteristicData = 'No data';
  String _locationData = 'No location data';
  List<String> _csvLines = [
    'No log data yet.',
  ]; // Stores the latest CSV lines for display
  bool _isServiceRunning = false; // Tracks if the background service is active
  BluetoothAdapterState _bluetoothAdapterState =
      BluetoothAdapterState.unknown; // Current Bluetooth adapter state

  // Subscription to listen for changes in the Bluetooth adapter state
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  String? _currentCsvFilePath; // Track the current session's CSV file path

  @override
  void initState() {
    super.initState();
    debugPrint('UI: initState called.');
    _checkServiceStatus(); // Check the initial status of the background service
    _listenToService(); // Start listening for updates from the background service
    _readLatestCsvLines(); // Read and display initial CSV log entries
    _listenToBluetoothAdapterState(); // Start listening to Bluetooth adapter state
  }

  /// Listens to the global Bluetooth adapter state and updates the UI accordingly.
  /// Also stops the logging service if Bluetooth is turned off.
  void _listenToBluetoothAdapterState() {
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      debugPrint('UI: Bluetooth adapter state changed to: $state');
      setState(() {
        _bluetoothAdapterState =
            state; // Update the UI with the new Bluetooth state
      });
      // If Bluetooth is off and the service is running, stop the logging gracefully.
      if (state != BluetoothAdapterState.on && _isServiceRunning) {
        Utils.showSnackBar('Bluetooth is off. Stopping logging.', context);
        _stopLogging(); // Automatically stop if Bluetooth turns off
      }
    });
  }

  /// Checks if the background service is currently running and updates the UI state.
  void _checkServiceStatus() async {
    debugPrint('UI: Checking background service status...');
    bool isRunning = await FlutterBackgroundService().isRunning();
    setState(() {
      _isServiceRunning = isRunning;
      _connectionStatus = isRunning
          ? 'Service is running...'
          : 'Service Stopped';
      disableDeleteButton = isRunning ? true : false;
    });
    debugPrint(
      'UI: Background service status: $_connectionStatus (isRunning: $_isServiceRunning)',
    );
  }

  /// Listens for messages (`updateUI`, `stopService`) from the background service
  /// and updates the UI accordingly.
  void _listenToService() {
    debugPrint('UI: Listening for service updates...');
    FlutterBackgroundService().on('updateUI').listen((data) {
      if (!mounted || data == null) {
        debugPrint(
          'UI: updateUI received, but widget not mounted or data is null.',
        );
        return; // Ensure widget is still mounted and data is not null
      }
      // Only update if service is not already stopped
      if (!_isServiceRunning) {
        debugPrint('UI: updateUI ignored because service is stopped.');
        return;
      }
      debugPrint('UI: Received updateUI: $data');
      setState(() {
        _connectionStatus = data['status'] ?? _connectionStatus;
        _characteristicData = data['btData'] ?? _characteristicData;
        _locationData = data['locationData'] ?? _locationData;
        _isServiceRunning = true; // Only set to true if not stopped
        disableDeleteButton = true;
      });
      _readLatestCsvLines(); // Periodically update the displayed CSV lines
    });

    FlutterBackgroundService().on('stopService').listen((event) {
      if (!mounted) {
        debugPrint('UI: stopService received, but widget not mounted.');
        return; // Ensure widget is still mounted
      }
      debugPrint('UI: Received stopService command.');
      setState(() {
        _isServiceRunning = false; // Service has stopped
        _connectionStatus = 'Service Stopped';
        _characteristicData = 'Aucune donnée'; // Clear displayed data
        _locationData = 'Aucune donnée GPS';
        disableDeleteButton = false;
      });
    });
  }

  @override
  void dispose() {
    debugPrint('UI: dispose called. Cleaning up...');
    _deviceNameController.dispose(); // Dispose of the text editing controller
    _adapterStateSubscription
        ?.cancel(); // Cancel the Bluetooth state subscription
    super.dispose();
  }

  /// Initiates the logging process.
  /// This includes requesting permissions, checking Bluetooth state, and starting the background service.
  Future<void> _startLogging() async {
    debugPrint('UI: Start Logging button pressed.');
    await Utils.requestPermissions();
    debugPrint('UI: Permissions re-checked.');

    // Perform pre-checks before attempting to start the service:
    if (Platform.isAndroid && !await Permission.notification.isGranted) {
      Utils.showSnackBar(
        'Notification permission is required to run in the background.',
        context,
      );
      debugPrint('UI: Notification permission denied.');
      return;
    }
    // Check for either LocationAlways or LocationWhenInUse for GPS logging.
    if (!(await Permission.locationAlways.isGranted ||
        await Permission.locationWhenInUse.isGranted)) {
      Utils.showSnackBar(
        'Location permission (Always or While in Use) is required for GPS logging.',
        context,
      );
      debugPrint('UI: Location permission denied.');
      return;
    }

    // Get the *current* Bluetooth adapter state directly before starting.
    BluetoothAdapterState currentBluetoothState =
        await FlutterBluePlus.adapterState.first;
    debugPrint('UI: Current Bluetooth adapter state: $currentBluetoothState');

    if (currentBluetoothState != BluetoothAdapterState.on) {
      Utils.showSnackBar(
        'Bluetooth is OFF. Attempting to turn on Bluetooth...',
        context,
      );
      debugPrint('UI: Bluetooth is OFF, attempting to turn on...');
      await FlutterBluePlus.turnOn(); // Attempt to turn on Bluetooth programmatically

      // Wait for the Bluetooth adapter to actually become ON, with a timeout.
      try {
        currentBluetoothState = await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 10)); // Max 10 seconds to turn on
        debugPrint('UI: Bluetooth adapter successfully turned ON.');
      } on TimeoutException {
        Utils.showSnackBar(
          'Bluetooth did not turn on in time. Please enable it manually.',
          context,
        );
        debugPrint('UI: Bluetooth did not turn on within timeout.');
        return;
      } catch (e) {
        Utils.showSnackBar(
          'Error turning on Bluetooth: $e. Please enable it manually.',
          context,
        );
        debugPrint('UI: Error turning on Bluetooth: $e');
        return;
      }

      if (currentBluetoothState != BluetoothAdapterState.on) {
        // This case should ideally not be hit if the timeout and where clause work,
        // but as a final safeguard.
        Utils.showSnackBar(
          'Bluetooth is still off despite attempt. Please enable it manually.',
          context,
        );
        debugPrint(
          'UI: Bluetooth state check failed even after turnOn attempt.',
        );
        return;
      }
    }

    final String deviceName = _deviceNameController.text.trim();
    if (deviceName.isEmpty) {
      Utils.showSnackBar('VC_SENS_XXXXXX', context);
      debugPrint('UI: Device name is empty.');
      return;
    }

    // Generate a new CSV file path for this session
    final csvFilePath = await Utils.generateCsvFilePath(deviceName);
    setState(() {
      _currentCsvFilePath = csvFilePath;
    });

    final service = FlutterBackgroundService();
    var isRunning = await service.isRunning();
    if (isRunning) {
      // If service is already running, stop it gracefully before restarting to ensure a clean start.
      Utils.showSnackBar(
        'Stopping existing service before restart...',
        context,
      );
      debugPrint('UI: Service already running, invoking stopService...');
      service.invoke('stopService');
      // Wait until the service is really stopped
      int tries = 0;
      while (await service.isRunning() && tries < 20) {
        await Future.delayed(const Duration(milliseconds: 200));
        tries++;
      }
      debugPrint('UI: Service stopped after ${tries * 200} ms.');
    }

    // Start the background service and send the 'startLogging' command.
    try {
      debugPrint('UI: Starting background service...');
      await service
          .startService(); // Actually starts the Dart background isolate
      // --- ADDED DELAY HERE ---
      await Future.delayed(
        const Duration(milliseconds: 1000),
      ); // Give service time to initialize fully
      debugPrint('UI: Brief delay after service.startService().');

      service.invoke(
        'setAsForeground',
      ); // Request to keep the service in foreground mode
      service.invoke('startLogging', {
        'deviceName': deviceName,
        'csvFilePath': csvFilePath, // Pass the new path!
      }); // Send command with device name
      debugPrint(
        'UI: Background service started and startLogging command sent.',
      );

      setState(() {
        _isServiceRunning = true;
        _connectionStatus = 'Starting Service...';
        disableDeleteButton = true;
      });
      Utils.showSnackBar('Logging started.', context);
    } catch (e) {
      // Handle potential errors during service startup (e.g., permissions not granted)
      Utils.showSnackBar('Failed to start service: ${e.toString()}', context);
      debugPrint('UI: Failed to start service: $e');
      setState(() {
        _isServiceRunning = false;
        _connectionStatus = 'Service Start Failed';
        disableDeleteButton = false;
      });
    }
  }

  /// Stops the logging process by invoking the 'stopService' command on the background service.
  void _stopLogging() {
    debugPrint('UI: Stop Logging button pressed. Invoking stopService...');
    FlutterBackgroundService().invoke('stopService');
    setState(() {
      _isServiceRunning = false;
      _connectionStatus = 'Stopped';
      disableDeleteButton = false;
    });

    Utils.showSnackBar('Logging stopped.', context);
  }

  /// Reads the latest log entries from the CSV file and updates the UI display.
  Future<void> _readLatestCsvLines() async {
    if (_currentCsvFilePath == null) return;
    debugPrint('UI: Reading latest CSV lines...');
    final file = File(_currentCsvFilePath!);
    if (!await file.exists()) {
      setState(() => _csvLines = ['No log data yet.']);
      debugPrint('UI: CSV file does not exist.');
      return;
    }
    try {
      final lines = await file.readAsLines();
      const int numLinesToShow = 10; // Display the last 10 log entries
      if (lines.length > 1) {
        // Check if there's header + at least one data row
        // Get the last 'numLinesToShow' lines, ensuring we don't include the header in the count
        // unless it's explicitly needed (e.g., if there are fewer than 10 data lines).
        setState(
          () => _csvLines = lines.sublist(
            (lines.length - numLinesToShow).clamp(1, lines.length),
          ),
        );
        debugPrint(
          'UI: Displaying last ${lines.length > 1 ? (lines.length - 1) : 0} CSV entries.',
        );
      } else {
        setState(
          () => _csvLines = ['No data entries.'],
        ); // Only header exists or file is empty
        debugPrint('UI: CSV file exists but no data entries found.');
      }
    } catch (e) {
      setState(() => _csvLines = ['Error reading log file: $e']);
      debugPrint(
        'UI: Error reading CSV file: $e',
      ); // Log the error for debugging
    }
  }

  String? get temperature {
    final match = RegExp(
      r'Temp[:=]?\s*([-\d.]+)',
    ).firstMatch(_characteristicData);
    return match != null ? '${match.group(1)}°C' : null;
  }

  String? get humidity {
    final match = RegExp(
      r'Hum[:=]?\s*([-\d.]+)',
    ).firstMatch(_characteristicData);
    return match != null ? '${match.group(1)}%' : null;
  }

  String? get latitude {
    final match = RegExp(r'Lat[:=]?\s*([-\d.]+)').firstMatch(_locationData);
    if (match != null) {
      final value = double.tryParse(match.group(1)!);
      if (value != null) {
        return value.toStringAsFixed(2);
      }
    }
    return null;
  }

  String? get longitude {
    final match = RegExp(
      r'(Long|Lon)[:=]?\s*([-\d.]+)',
    ).firstMatch(_locationData);
    if (match != null) {
      final value = double.tryParse(match.group(2)!);
      if (value != null) {
        return value.toStringAsFixed(2);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VéloClimat'), // <-- FR
        elevation: 4, // Add a slight shadow to the app bar for depth
      ),
      body: SingleChildScrollView(
        // Use SingleChildScrollView to prevent content overflow on smaller screens
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch, // Stretch children horizontally
          children: [
            // Bluetooth Device Name Input Field
            TextField(
              controller: _deviceNameController,

              decoration: InputDecoration(
                labelText: 'Nom du capteur Bluetooth',
                hintText: 'Nom exact du capteur (ex: VC_SENS_X)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    8.0,
                  ), // Rounded corners for input field
                ),
                prefixIcon: const Icon(
                  Icons.bluetooth,
                ), // Bluetooth icon prefix
              ),
              enabled:
                  !_isServiceRunning, // Disable input when service is active
            ),
            const SizedBox(height: 20),

            // Bluetooth Status Indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _bluetoothAdapterState == BluetoothAdapterState.on
                      ? Icons
                            .bluetooth_connected // Icon for Bluetooth ON
                      : Icons.bluetooth_disabled, // Icon for Bluetooth OFF
                  color: _bluetoothAdapterState == BluetoothAdapterState.on
                      ? Colors
                            .blue
                            .shade700 // Blue for ON
                      : Colors.grey.shade600, // Grey for OFF
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  'Bluetooth : ${_bluetoothAdapterState.name.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _bluetoothAdapterState == BluetoothAdapterState.on
                        ? Colors.blue.shade700
                        : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Start/Stop Logging Button
            ElevatedButton.icon(
              onPressed: _isServiceRunning
                  ? _stopLogging
                  : _startLogging, // Toggle based on service status
              icon: Icon(_isServiceRunning ? Icons.stop : Icons.play_arrow),
              label: Text(
                _isServiceRunning ? 'Arrêter' : 'Démarrer',
                style: const TextStyle(fontSize: 18),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isServiceRunning
                    ? Colors.red.shade700
                    : Colors.green.shade700, // Red for stop, Green for start
                foregroundColor: Colors.white, // White text color
                padding: const EdgeInsets.symmetric(
                  vertical: 15,
                ), // Larger padding for better touch target
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    10,
                  ), // Rounded button corners
                ),
                elevation: 5, // Add shadow for a raised effect
              ),
            ),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                DeleteFilesButton(isDisabled: disableDeleteButton),
                const SizedBox(width: 16),
                ShareDataButton(),
              ],
            ),

            const SizedBox(height: 25),

            // Live Status Section
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatusRow(
                      'État du service :',
                      _connectionStatus,
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
                          label: 'Long',
                          value: longitude ?? '--',
                          color: Colors.green.shade700,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 25),

            // Latest Log Entries Section
            Text(
              'Dernières mesures :',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade800,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: _csvLines.isEmpty || _csvLines.first.startsWith('No')
                  ? Center(
                      child: Text(
                        _csvLines.first.startsWith('No')
                            ? 'Aucune donnée'
                            : _csvLines.first,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(
                            Colors.blue.shade50,
                          ),
                          columns: const [
                            DataColumn(label: Text('Date')),
                            DataColumn(label: Text('Temp')),
                            DataColumn(label: Text('Hum')),
                            DataColumn(label: Text('Lat')),
                            DataColumn(label: Text('Long')),
                            DataColumn(label: Text('Acc')),
                          ],
                          rows: _csvLines
                              .skip(1) // skip header
                              .where((line) => line.trim().isNotEmpty)
                              .toList()
                              .reversed // latest first
                              .map((line) {
                                final cells = line.split(',');
                                while (cells.length < 6) {
                                  cells.add('--');
                                }
                                return DataRow(
                                  cells: [
                                    DataCell(Text(cells[0])),
                                    DataCell(
                                      Text(
                                        cells[1],
                                        style: TextStyle(
                                          color: Colors.orange.shade700,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        cells[2],
                                        style: TextStyle(
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        cells[3],
                                        style: TextStyle(
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        cells[4],
                                        style: TextStyle(
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        cells[5],
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              })
                              .toList(),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 50), // Add some spacing at the bottom
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
