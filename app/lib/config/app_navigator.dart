import 'package:flutter/material.dart';

/// Cheie globală pentru navigare din push (FCM) când app e deja pornită.
class AppNavigator {
  AppNavigator._();
  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();
}
