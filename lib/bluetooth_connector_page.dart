// --- UI (Page) ---
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensor_logging/widgets/bluetooth_indicator.dart';
import 'package:sensor_logging/widgets/connection_button.dart';
import 'package:sensor_logging/widgets/delete_files_button.dart';
import 'package:sensor_logging/utils.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:sensor_logging/widgets/live_status_card.dart';
import 'package:sensor_logging/widgets/log_table.dart';
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
  String _connectionStatus = 'Service arrêté';
  String _characteristicData = 'Aucune donnée';
  String _locationData = 'Aucune donnée GPS';
  List<String> _csvLines = [
    'Aucune donnée',
  ]; // Stores the latest CSV lines for display
  bool _isServiceRunning = false; // Tracks if the background service is active
  BluetoothAdapterState _bluetoothAdapterState =
      BluetoothAdapterState.unknown; // Current Bluetooth adapter state

  // Subscription to listen for changes in the Bluetooth adapter state
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  String? _currentCsvFilePath; // Track the current session's CSV file path
  bool _isConnecting = false; // <-- Ajouté

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
        Utils.showSnackBar(
          'Le Bluetooth est désactivé. Arrêt de journalisation.',
          context,
        );
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
          ? 'Service en exécution...'
          : 'Service arrêté';
      disableDeleteButton = isRunning || _isConnecting ? true : false;
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
        return;
      }
      debugPrint('UI: Received updateUI: $data');
      setState(() {
        _connectionStatus = data['status'] ?? _connectionStatus;
        _characteristicData = data['btData'] ?? _characteristicData;
        _locationData = data['locationData'] ?? _locationData;
        // <-- Ajout : met à jour _isConnecting selon isScanning
        if (data.containsKey('isScanning')) {
          _isConnecting = data['isScanning'] == true;
        }
        // Only set _isServiceRunning to true if status is not "Service arrêté"
        _isServiceRunning = data['status'] == 'Service arrêté'
            ? false
            : _isServiceRunning;
        disableDeleteButton = data['status'] == 'Service arrêté' ? false : true;
      });
      // Affiche le toast si demandé
      if (data['showToast'] != null &&
          data['showToast'].toString().isNotEmpty) {
        Utils.showSnackBar(data['showToast'].toString(), context);
      }
      _readLatestCsvLines();
    });

    FlutterBackgroundService().on('stopService').listen((event) {
      if (!mounted) {
        debugPrint('UI: stopService received, but widget not mounted.');
        return;
      }
      debugPrint('UI: Received stopService command.');
      setState(() {
        _isServiceRunning = false;
        _connectionStatus = 'Service Stopped';
        _characteristicData = 'Aucune donnée';
        _locationData = 'Aucune donnée GPS';
        disableDeleteButton = false;
        _isConnecting = false; // Toujours désactiver le loader à l'arrêt
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
    setState(() {
      _isConnecting = true; // <-- Ajouté
    });
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
      await service.startService();
      await Future.delayed(const Duration(milliseconds: 1000));
      service.invoke('setAsForeground');
      service.invoke('startLogging', {
        'deviceName': deviceName,
        'csvFilePath': csvFilePath,
      });
      debugPrint(
        'UI: Background service started and startLogging command sent.',
      );

      setState(() {
        _isServiceRunning = true;
        _connectionStatus = 'Starting Service...';
        disableDeleteButton = true;
        _isConnecting = false; // <-- Ajouté
      });
      Utils.showSnackBar('Logging started.', context);
    } catch (e) {
      Utils.showSnackBar('Failed to start service: ${e.toString()}', context);
      debugPrint('UI: Failed to start service: $e');
      setState(() {
        _isServiceRunning = false;
        _connectionStatus = 'Service Start Failed';
        disableDeleteButton = false;
        _isConnecting = false; // <-- Ajouté
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
      _isConnecting = false; // <-- Ajouté
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
            BluetoothIndicator(bluetoothAdapterState: _bluetoothAdapterState),

            const SizedBox(height: 20),

            // Start/Stop Logging Button
            ConnectionButton(
              isConnecting: _isConnecting,
              isServiceRunning: _isServiceRunning,
              startLogging: _startLogging,
              stopLogging: _stopLogging,
              onServiceStatusChanged: _checkServiceStatus,
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
            LiveStatusCard(
              connectionStatus: _connectionStatus,
              temperature: temperature,
              humidity: humidity,
              latitude: latitude,
              longitude: longitude,
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
                  : LogTable(csvLines: _csvLines),
            ),
            const SizedBox(height: 50), // Add some spacing at the bottom
          ],
        ),
      ),
    );
  }
}
