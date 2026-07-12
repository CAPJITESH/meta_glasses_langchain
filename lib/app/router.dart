import 'package:flutter/material.dart';

import '../features/download_llm_model/screens/download_llm_screen.dart';
import '../features/home/screens/home_screen.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/home':
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case '/download-model':
        return MaterialPageRoute(builder: (_) => const DownloadLlmScreen());
      default:
        return MaterialPageRoute(builder: (_) => const DownloadLlmScreen());
    }
  }
}
