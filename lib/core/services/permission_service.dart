import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  Future<bool> ensureStorageOrNetworkPermission() async {
    // For app-sandboxed directories via path_provider, explicit storage permission
    // is not required on modern Android/iOS. The app can access its own directories.
    // This method can be used to request permissions if needed in the future.
    return true;
  }

  Future<bool> requestStoragePermission() async {
    final status = await Permission.storage.request();
    return status.isGranted || status.isDenied;
  }

  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }
}
