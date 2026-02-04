import 'package:flutter/material.dart';
import 'workout_session_service.dart';
import 'screens/workout_session_screen.dart';
export 'screens/workout_session_screen.dart';
export 'screens/session_overview_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final sessionService = WorkoutSessionService();
    // For web compatibility, skip database initialization for now
    // await sessionService.initialize();
    runApp(MyApp(sessionService: sessionService));
  } catch (e) {
    print('Error initializing app: $e');
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Error initializing app. Check console for details.'),
        ),
      ),
    ));
  }
}

class MyApp extends StatelessWidget {
  final WorkoutSessionService sessionService;

  const MyApp({super.key, required this.sessionService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Omnitrain',
      theme: ThemeData.dark(useMaterial3: true),
      home: HomeScreen(sessionService: sessionService),
    );
  }
}

class HomeScreen extends StatelessWidget {
  final WorkoutSessionService sessionService;

  const HomeScreen({super.key, required this.sessionService});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Omnitrain'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('New Workout Session'),
            onPressed: () async {
              if (sessionService.currentSession == null) {
                await sessionService.createNewSession();
              }
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WorkoutSessionScreen(sessionService: sessionService),
              ));
            },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ),
      ),
    );
  }
}

