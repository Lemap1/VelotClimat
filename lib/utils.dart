import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class Utils {
  static String? csvPath;

  /// Requests essential permissions for the app: Notifications (for Android 13+),
  /// Bluetooth (for Android 12+), Location (Always/WhileInUse), and Storage.
  static Future<void> requestPermissions() async {
    debugPrint('Requesting permissions...');

    // Request notification permission for Android 13+ to ensure foreground service notifications work.
    if (Platform.isAndroid) {
      var status = await Permission.notification.status;
      if (status.isDenied) {
        debugPrint('Requesting notification permission...');
        await Permission.notification.request();
      }
    }

    // Request Bluetooth permissions for Android 12 (API 31) and above
    if (Platform.isAndroid && await Permission.bluetooth.status.isDenied) {
      debugPrint('Requesting general Bluetooth permission...');
      await Permission.bluetooth.request();
    }
    if (Platform.isAndroid && await Permission.bluetoothScan.status.isDenied) {
      debugPrint('Requesting Bluetooth Scan permission...');
      await Permission.bluetoothScan.request();
    }
    if (Platform.isAndroid &&
        await Permission.bluetoothConnect.status.isDenied) {
      debugPrint('Requesting Bluetooth Connect permission...');
      await Permission.bluetoothConnect.request();
    }
    if (Platform.isAndroid &&
        await Permission.bluetoothAdvertise.status.isDenied) {
      debugPrint('Requesting Bluetooth Advertise permission...');
      await Permission.bluetoothAdvertise.request();
    }

    // Request location permissions. Prioritize "Always" for continuous background GPS logging.
    var locationStatus = await Permission.location.status;
    if (locationStatus.isDenied) {
      debugPrint('Requesting location permission...');
      await Permission.location.request();
    }

    // If location is granted (either WhileInUse or Always), specifically request "Always"
    // for robust background location tracking.
    if (await Permission.location.isGranted) {
      var backgroundLocationStatus = await Permission.locationAlways.status;
      if (backgroundLocationStatus.isDenied) {
        debugPrint('Requesting background location permission...');
        // This will open a dialog to guide the user to settings if needed for "Always" permission.
        await Permission.locationAlways.request();
      }
    }

    // Request storage permission for Android for CSV file saving in external storage
    if (Platform.isAndroid) {
      var storageStatus = await Permission.storage.status;
      if (storageStatus.isDenied) {
        debugPrint('Requesting storage permission...');
        await Permission.storage.request();
      }
    }
    debugPrint('Permissions requested.');
  }

  /// Determines the file path for the CSV log.
  /// On Android, it uses `getExternalStorageDirectory` for easier user access.
  /// On iOS, it uses `getApplicationDocumentsDirectory`.
  static Future<String> get csvFilePath async {
    Directory? directory;

    if (csvPath == null) {
      if (Platform.isAndroid) {
        // getExternalStorageDirectory requires WRITE_EXTERNAL_STORAGE permission on older Android,
        // but on newer versions, it's typically managed by `requestLegacyExternalStorage` or scoped storage.
        directory = await getExternalStorageDirectory();
      } else {
        // For iOS, the application's document directory is appropriate.
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory == null) {
        throw Exception("Could not get application directory for CSV storage.");
      }
      csvPath = '${directory.path}/sensor_log_${DateTime.now()}.csv';
      return csvPath!;
    }

    return csvPath!;
  }
}
