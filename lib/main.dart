import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui'; // Required for DartPluginRegistrant.ensureInitialized()
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'; // For Bluetooth operations
import 'package:geolocator/geolocator.dart'; // For GPS location
import 'package:csv/csv.dart'; // For CSV file generation
import 'package:sensor_logging/bluetooth_connector_page.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sensor_logging/utils.dart';

// --- Background Service Configuration ---

// IMPORTANT: Update these UUIDs if your sensor uses different ones
// These are example UUIDs for a generic Environmental Sensing Service and a custom characteristic.
final Guid SERVICE_UUID = Guid("181A");
final Guid CHARACTERISTIC_UUID = Guid("FF01");

/// Initializes the background service. This sets up the Android and iOS configurations.
/// It also requests necessary permissions before the service attempts to start.
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const notificationChannelId = "my_app_service";
  const notificationId = 888;

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    notificationChannelId, // id
    'Sensor data logger', // title
    description:
        'This channel is used for the sensor data logging', // description
    importance: Importance.low, // importance must be at low or higher level
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);
  // Request necessary permissions (notifications and location) before configuring the service.
  // This ensures the user is prompted early.
  await Utils.requestPermissions();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart, // The entry point function for the background service
      autoStart: false, // We will start it manually from the UI
      isForegroundMode:
          true, // Runs as a foreground service to prevent system termination
      notificationChannelId:
          notificationChannelId, // Unique ID for the notification channel
      initialNotificationTitle:
          'Sensor data logger', // Initial title displayed in the ongoing notification
      initialNotificationContent:
          'Initializing...', // Initial content of the notification
      foregroundServiceNotificationId:
          notificationId, // Unique ID for the foreground service notification
      // IMPORTANT: Declare foreground service types for Android 10 (API 29) and above.
      // These should match the 'android:foregroundServiceType' in your AndroidManifest.xml.
    ),
    iosConfiguration: IosConfiguration(),
  );
}

class ForegroundServiceType {}

/// Helper to get Android SDK version

/// The entry point for the background service. This code runs in an isolated Dart Isolate.
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Ensure Flutter plugins (like FlutterBluePlus and Geolocator) are initialized in this isolate.
  DartPluginRegistrant.ensureInitialized();
  debugPrint('Background service: onStart initiated.');

  // --- Background Task State Variables ---
  String? deviceName;
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? targetCharacteristic;
  Timer? logTimer; // Timer for periodic data collection
  StreamSubscription<BluetoothConnectionState>?
  connectionStateSubscription; // Listens for BT device disconnection
  StreamSubscription<BluetoothAdapterState>?
  adapterStateSubscription; // Listens for global BT adapter state changes

  String? csvFilePath; // <-- Add this to track the current session's CSV file

  // --- Foreground/Background Mode Management for Android ---
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService(); // Puts the service into foreground mode
      debugPrint('Background service: Set as foreground.');
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService(); // Puts the service into background mode
      debugPrint('Background service: Set as background.');
    });
  }

  // --- Stop Service Command Listener ---
  // This listener handles requests from the UI to stop the background service.
  service.on('stopService').listen((event) async {
    debugPrint(
      'Background service: stopService command received. Cleaning up...',
    );
    // Clean up all resources to prevent leaks and ensure a graceful shutdown.
    logTimer
        ?.cancel(); // Stop the periodic logging timer - Removed 'await' as cancel() returns void
    await connectionStateSubscription
        ?.cancel(); // Cancel device connection state listener
    await adapterStateSubscription
        ?.cancel(); // Cancel Bluetooth adapter state listener

    // Attempt to disconnect from the Bluetooth device if it's connected.
    try {
      if (connectedDevice != null &&
          (await connectedDevice!.connectionState.first) ==
              BluetoothConnectionState.connected) {
        debugPrint(
          'Background service: Disconnecting from Bluetooth device...',
        );
        await connectedDevice!.disconnect();
        debugPrint(
          'Background service: Bluetooth device disconnected cleanly.',
        );
      }
    } catch (e) {
      debugPrint('Background service: Error disconnecting device on stop: $e');
    }

    // Stop any active Bluetooth scanning.
    try {
      // Access the current value of the isScanning stream using .first
      if (await FlutterBluePlus.isScanning.first) {
        debugPrint('Background service: Stopping Bluetooth scan...');
        await FlutterBluePlus.stopScan();
        debugPrint('Background service: Bluetooth scan stopped cleanly.');
      }
    } catch (e) {
      debugPrint('Background service: Error stopping scan on stop: $e');
    }

    service.stopSelf(); // Stops the background service itself
    debugPrint('Background service: Service stopped itself.');
    // Update UI to reflect that the service has stopped and clear data displays.
    service.invoke('updateUI', {
      'status': 'Service Stopped',
      'btData': 'No data',
      'locationData': 'No location data',
    });
  });

  // --- Listen for Bluetooth Adapter State Changes ---
  // This is crucial for handling cases where Bluetooth is turned off by the user.
  adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
    debugPrint(
      'Background service: Bluetooth adapter state changed to: $state',
    );
    if (state != BluetoothAdapterState.on) {
      // If Bluetooth is off or unavailable, notify the UI and stop the logging service.
      service.invoke('updateUI', {
        'status': 'Bluetooth OFF. Stopping logging.',
        'btData': 'Bluetooth Off',
        'locationData': 'No location data',
      });
      debugPrint(
        'Background service: Bluetooth adapter turned off. Stopping service.',
      );
      service.invoke('stopService'); // Request to stop the service
    } else {
      // Bluetooth is ON, update status if logging is active.
      if (logTimer?.isActive ?? false) {
        service.invoke('updateUI', {'status': 'Bluetooth ON. Logging...'});
      }
    }
  });

  // --- Listen for 'startLogging' command from the UI ---
  service.on('startLogging').listen((data) async {
    debugPrint('Background service: startLogging command received.');
    if (data == null) {
      debugPrint('Background service: startLogging data is null, returning.');
      return;
    }
    deviceName = data['deviceName'];
    csvFilePath = data['csvFilePath']; // <-- Get the path from UI

    // Ensure CSV header for this session's file
    await _ensureCsvHeader(csvFilePath);

    // Prevent starting logging if it's already active.
    if (logTimer?.isActive ?? false) {
      service.invoke('updateUI', {
        'status': 'Logging already active for "$deviceName".',
      });
      debugPrint('Background service: Logging already active.');
      return;
    }

    service.invoke('updateUI', {
      'status': 'Scanning for "$deviceName"...',
      'btData': 'No data',
      'locationData': 'No location data',
    });
    debugPrint('Background service: UI updated to scanning status.');

    // Explicitly check if Bluetooth is enabled before starting any scan/connection.
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      service.invoke('updateUI', {
        'status': 'Error: Bluetooth is OFF. Cannot start logging.',
      });
      service.invoke('stopService'); // Stop service as Bluetooth is required
      debugPrint('Background service: Bluetooth is OFF, stopping service.');
      return;
    }

    // --- Connect to Bluetooth Device ---
    try {
      debugPrint(
        'Background service: Attempting to connect to Bluetooth device.',
      );
      // Ensure a clean state before attempting a new connection:
      if (connectedDevice != null &&
          (await connectedDevice!.connectionState.first) ==
              BluetoothConnectionState.connected) {
        debugPrint(
          'Background service: Previous device was connected, disconnecting...',
        );
        await connectedDevice!.disconnect();
      }
      connectionStateSubscription?.cancel(); // Cancel any old subscription
      connectedDevice = null;
      targetCharacteristic = null;
      FlutterBluePlus.scanResults.drain(); // Clear previous scan results
      // Access the current value of the isScanning stream using .first
      if (await FlutterBluePlus.isScanning.first) {
        debugPrint(
          'Background service: Stopping any ongoing Bluetooth scan...',
        );
        await FlutterBluePlus.stopScan(); // Stop any ongoing scan
      }

      debugPrint(
        'Background service: Starting new Bluetooth scan for 15 seconds...',
      );
      // Start a new Bluetooth scan with a timeout.
      // We use `withRemoteIds` as empty to scan for all devices and then filter by name.
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        withRemoteIds: [], // Scan for all devices, then filter by name
      );

      // Listen to the stream of scan results to find the target device.
      // The `await for` loop will continue until `stopScan` is called or timeout.
      await for (List<ScanResult> results in FlutterBluePlus.scanResults) {
        for (ScanResult r in results) {
          debugPrint(
            'Background service: Found device: ${r.device.platformName}',
          );
          // Filter by platformName (advertised name) allowing for case-insensitive partial matches.
          if (r.device.platformName.toLowerCase().contains(
            deviceName!.toLowerCase(),
          )) {
            connectedDevice = r.device;
            debugPrint(
              'Background service: Target device "$deviceName" found!',
            );
            await FlutterBluePlus.stopScan(); // Device found, stop scanning immediately
            break; // Exit inner loop (found device)
          }
        }
        if (connectedDevice != null) {
          break; // Exit outer stream listening loop (device found)
        }
      }

      // If the device was not found after the scan, stop the service.
      if (connectedDevice == null) {
        service.invoke('updateUI', {
          'status': 'Device "$deviceName" not found after scan.',
        });
        service.invoke('stopService');
        debugPrint(
          'Background service: Target device not found, stopping service.',
        );
        return;
      }

      // --- Connect to the discovered device ---
      debugPrint(
        'Background service: Connecting to ${connectedDevice!.platformName}...',
      );
      await connectedDevice!.connect(autoConnect: false);
      service.invoke('updateUI', {
        'status': 'Connected to $deviceName. Discovering services...',
      });
      debugPrint('Background service: Connected. Discovering services...');

      // Listen for disconnection events specific to this connected device.
      // If the device disconnects unexpectedly, we'll stop the service cleanly.
      connectionStateSubscription = connectedDevice!.connectionState.listen((
        state,
      ) async {
        debugPrint(
          'Background service: Device connection state changed to: $state',
        );
        if (state == BluetoothConnectionState.disconnected) {
          service.invoke('updateUI', {
            'status': '$deviceName disconnected. Stopping logging.',
          });
          debugPrint(
            'Background service: Device disconnected. Stopping service.',
          );
          service.invoke(
            'stopService',
          ); // Stop service on unexpected disconnection
        }
      });

      // Discover services and find the target characteristic.
      List<BluetoothService> services = await connectedDevice!
          .discoverServices();
      debugPrint('Background service: Discovered ${services.length} services.');
      for (var s in services) {
        debugPrint('Background service: Service UUID: ${s.uuid}');
        if (s.uuid == SERVICE_UUID) {
          debugPrint(
            'Background service: Found target SERVICE_UUID: ${s.uuid}',
          );
          for (var c in s.characteristics) {
            debugPrint('Background service: Characteristic UUID: ${c.uuid}');
            if (c.uuid == CHARACTERISTIC_UUID) {
              targetCharacteristic = c;
              debugPrint(
                'Background service: Found target CHARACTERISTIC_UUID: ${c.uuid}',
              );
              break; // Characteristic found
            }
          }
        }
      }

      // If the target characteristic is not found, disconnect and stop the service.
      if (targetCharacteristic == null) {
        service.invoke('updateUI', {
          'status': 'Characteristic not found on $deviceName.',
        });
        debugPrint(
          'Background service: Target characteristic not found. Disconnecting...',
        );
        await connectedDevice!.disconnect(); // Disconnect cleanly
        service.invoke('stopService');
        return;
      }

      // --- Start Periodic Data Collection & Logging ---
      // This timer will trigger the data collection function at a fixed interval.
      debugPrint('Background service: Starting periodic log timer.');
      logTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
        if (connectedDevice != null && targetCharacteristic != null) {
          // Only proceed if device and characteristic are still valid.
          await _collectAndLogData(
            service,
            connectedDevice!,
            targetCharacteristic!,
            csvFilePath, // Pass the session's CSV file path
          );
        } else {
          // If for some reason device or characteristic becomes null, stop logging.
          service.invoke('updateUI', {
            'status':
                'Error: Bluetooth device/characteristic unavailable. Stopping.',
          });
          debugPrint(
            'Background service: Device or characteristic became null during logging. Stopping.',
          );
          service.invoke('stopService');
        }
      });

      service.invoke('updateUI', {
        'status': 'Connected & Logging every second.',
      });
      debugPrint('Background service: Logging successfully initiated.');
    } catch (e) {
      // Catch any errors during Bluetooth scanning, connection, or service discovery.
      service.invoke('updateUI', {
        'status': 'Bluetooth Error: ${e.toString()}',
      });
      debugPrint(
        'Background service: Critical Bluetooth error during setup: $e',
      );
      service.invoke('stopService'); // Stop service on critical Bluetooth error
    }
  });
}

/// Collects Bluetooth and GPS data, logs it to a CSV, and updates the UI.
/// This function runs periodically in the background service.
Future<void> _collectAndLogData(
  ServiceInstance service,
  BluetoothDevice device,
  BluetoothCharacteristic characteristic,
  String? csvFilePath,
) async {
  debugPrint('Background service: _collectAndLogData called.');
  final now = DateTime.now();
  String timestamp = now
      .toIso8601String(); // ISO 8601 format for consistent timestamps

  double? temp, hum, lat, lon, accuracy;
  String btDataStr = 'No data';
  String locationDataStr = 'No location data';

  // --- Get Bluetooth data ---
  try {
    debugPrint('Background service: Checking Bluetooth connection state...');
    // Check connection state *immediately* before attempting to read the characteristic.
    // This helps avoid errors if the device disconnects right before a read.
    if (await device.connectionState.first ==
        BluetoothConnectionState.connected) {
      debugPrint(
        'Background service: Device connected. Attempting to read characteristic...',
      );
      List<int> value = await characteristic
          .read(); // Read the characteristic's value
      if (value.length >= 8) {
        // Expecting at least 8 bytes for two Float32 values
        final byteData = ByteData.view(Uint8List.fromList(value).buffer);
        // Assuming little endian as per original code. Adjust if your sensor uses big endian.
        temp = byteData.getFloat32(
          0,
          Endian.little,
        ); // First 4 bytes for temperature
        hum = byteData.getFloat32(
          4,
          Endian.little,
        ); // Next 4 bytes for humidity
        btDataStr =
            'Temp: ${temp.toStringAsFixed(2)} °C, Hum: ${hum.toStringAsFixed(2)} %';
        debugPrint('Background service: Bluetooth data read: $btDataStr');
      } else {
        btDataStr =
            'Error: Not enough bytes (${value.length}) from BT device. Expected 8+';
        debugPrint(
          'Background service: $btDataStr',
        ); // Log the error internally
      }
    } else {
      btDataStr = 'Device disconnected.';
      debugPrint('Background service: $btDataStr');
      // IMPORTANT: Do NOT stop the service here. The `_connectionStateSubscription` in `onStart`
      // will handle the disconnection and stop the service gracefully.
    }
  } catch (e) {
    btDataStr = 'Error reading BT data: $e';
    debugPrint('Background service: $btDataStr'); // Log the error internally
    // IMPORTANT: Do NOT stop the service here. Allow the service to continue attempting readings.
  }

  // --- Get GPS data ---
  try {
    debugPrint('Background service: Checking GPS service and permissions...');
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    // Check both service enablement and permission status.
    if (serviceEnabled &&
        (await Geolocator.checkPermission() == LocationPermission.whileInUse ||
            await Geolocator.checkPermission() == LocationPermission.always)) {
      debugPrint(
        'Background service: GPS enabled and permission granted. Getting current position...',
      );
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy:
            LocationAccuracy.best, // Request the best available accuracy
        timeLimit: const Duration(
          seconds: 5,
        ), // Added timeLimit to prevent indefinite waiting
      );
      lat = position.latitude;
      lon = position.longitude;
      accuracy = position.accuracy;
      locationDataStr =
          'Lat: ${lat.toStringAsFixed(6)}, Lon: ${lon.toStringAsFixed(6)}';
      debugPrint('Background service: GPS data: $locationDataStr');
    } else {
      locationDataStr = 'GPS service/permission disabled or denied.';
      debugPrint('Background service: $locationDataStr');
    }
  } catch (e) {
    locationDataStr = 'Error getting location: $e';
    debugPrint(
      'Background service: $locationDataStr',
    ); // Log the error internally
  }

  // --- Append data to CSV ---
  debugPrint('Background service: Appending data to CSV...');
  await _appendToCsv([
    timestamp,
    temp?.toStringAsFixed(2) ?? 'N/A', // Use 'N/A' if data is null
    hum?.toStringAsFixed(2) ?? 'N/A',
    lat?.toString() ?? 'N/A',
    lon?.toString() ?? 'N/A',
    accuracy?.toStringAsFixed(2) ?? 'N/A',
  ], csvFilePath);
  debugPrint('Background service: Data appended to CSV.');

  // --- Send data to UI ---
  // Update the UI with the latest status and collected data.
  service.invoke('updateUI', {
    // Provide a more concise status message for the UI, indicating if BT/GPS had errors.
    'status':
        'BLT: ${btDataStr.contains("Error") ? "Error" : "OK"}, GPS: ${locationDataStr.contains("Error") ? "Error" : "OK"}',
    'btData': btDataStr,
    'locationData': locationDataStr,
  });
  debugPrint('Background service: UI updated with latest data.');
}

// --- CSV File Management ---

/// Ensures that the CSV file exists and contains the header row.
/// If the file doesn't exist or is empty, it writes the header.
Future<void> _ensureCsvHeader(String? csvFilePath) async {
  if (csvFilePath == null) return;
  final file = File(csvFilePath);
  if (!await file.exists() || (await file.readAsString()).trim().isEmpty) {
    final header = [
      'Timestamp',
      'Temperature',
      'Humidity',
      'Latitude',
      'Longitude',
      'Accuracy',
    ];
    final csvString = const ListToCsvConverter().convert([header]);
    await file.writeAsString('$csvString\n', mode: FileMode.write);
    debugPrint('CSV header ensured.');
  } else {
    debugPrint('CSV header already present.');
  }
}

/// Appends a new row of data to the CSV log file.
Future<void> _appendToCsv(List<dynamic> row, String? csvFilePath) async {
  if (csvFilePath == null) return;
  final file = File(csvFilePath);
  final csvString = const ListToCsvConverter().convert([row]);
  await file.writeAsString('$csvString\n', mode: FileMode.append);
}

// --- Main Application Entry Point ---
void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ensure Flutter widgets are initialized
  debugPrint('Main: WidgetsFlutterBinding initialized.');

  await initializeService(); // Initialize the background service configuration
  debugPrint('Main: Background service initialized.');

  // Enable verbose logging for FlutterBluePlus to aid in debugging Bluetooth issues.
  FlutterBluePlus.setLogLevel(LogLevel.verbose);
  debugPrint('Main: FlutterBluePlus log level set to verbose.');

  runApp(const MyApp());
  debugPrint('Main: MyApp started.');
}

// --- Main Flutter App Widget ---
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VéloClimat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const BluetoothConnectorPage(), // No csvFilePath needed here
    );
  }
}
