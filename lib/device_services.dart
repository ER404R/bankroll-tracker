import 'package:flutter/services.dart';

class DeviceServices {
  static const channel = MethodChannel('feltledger/device');
  static Future<Map<Object?, Object?>> appInfo() async =>
      await channel.invokeMapMethod<Object?, Object?>('appInfo') ?? {};
  static Future<bool> authenticate() async =>
      await channel.invokeMethod<bool>('authenticate') ?? false;
  static Future<bool> enableNotifications() async =>
      await channel.invokeMethod<bool>('notifications') ?? false;
  static Future<void> remindAt(DateTime time) async =>
      channel.invokeMethod('reminder', {'at': time.millisecondsSinceEpoch});
  static Future<void> cancelReminder() async =>
      channel.invokeMethod('cancelReminder');
}
