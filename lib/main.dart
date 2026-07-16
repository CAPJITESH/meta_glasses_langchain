import 'dart:io';
import 'package:flutter/material.dart';
import 'package:qualcom_hacks/features/download_llm_model/screens/download_llm_screen.dart';
import 'package:qualcom_hacks/features/glasses_voice/screens/glasses_voice_screen.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/services/storage_service.dart';
import 'features/download_llm_model/data/llm_download_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService().init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<String> _initialRouteFuture;

  @override
  void initState() {
    super.initState();
    _initialRouteFuture = _determineInitialRoute();
  }

  Future<String> _determineInitialRoute() async {
    try {
      final repository = LlmDownloadRepository();
      await repository.init();
      final savedLlm = await repository.getSavedLlmModel();
      final savedEmbedding = await repository.getSavedEmbeddingModel();

      if (savedLlm != null &&
          savedLlm.isDownloaded &&
          savedLlm.localPath != null &&
          await File(savedLlm.localPath!).exists() &&
          savedEmbedding != null &&
          savedEmbedding.isDownloaded &&
          savedEmbedding.localPath != null &&
          await File(savedEmbedding.localPath!).exists()) {
        return '/glasses';
      }

      return '/download-model';
    } catch (e) {
      return '/download-model';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _initialRouteFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            title: 'Glasses Assistant',
            theme: AppTheme.dark(),
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        return MaterialApp(
          title: 'Glasses Assistant',
          theme: AppTheme.dark(),
          onGenerateRoute: AppRouter.generateRoute,
          home: snapshot.data == '/glasses'
              ? const GlassesVoiceScreen()
              : const DownloadLlmScreen(),
        );
      },
    );
  }
}
