import 'dart:io';
import 'package:flutter/material.dart';
import 'app/router.dart';
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
      final savedModel = await repository.getSavedModel();

      if (savedModel != null && savedModel.isDownloaded) {
        // Verify the file actually exists at the stored path
        if (savedModel.localPath != null && await File(savedModel.localPath!).exists()) {
          return '/home';
        }
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
        String initialRoute = '/home';
        if (snapshot.hasData) {
          initialRoute = snapshot.data ?? '/home';
        }

        return MaterialApp(
          title: 'Flutter Demo',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          ),
          onGenerateRoute: AppRouter.generateRoute,
          initialRoute: initialRoute,
        );
      },
    );
  }
}
