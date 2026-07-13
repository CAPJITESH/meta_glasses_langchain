import 'package:flutter/material.dart';

import '../features/download_llm_model/screens/download_llm_screen.dart';
import '../features/glasses_voice/screens/glasses_voice_screen.dart';
import '../features/home/screens/home_screen.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/home':
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case '/download-model':
        return MaterialPageRoute(builder: (_) => const DownloadLlmScreen());
      case '/glasses':
        return MaterialPageRoute(builder: (_) => const GlassesVoiceScreen());
      default:
        return MaterialPageRoute(builder: (_) => const DownloadLlmScreen());
    }
  }
}
