import 'package:client/src/flow_canvas_screen.dart';
import 'package:client/theme/cyaichi_theme.dart';
import 'package:flutter/material.dart';

class CyaichiApp extends StatelessWidget {
  const CyaichiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CyaiChi',
      debugShowCheckedModeBanner: false,
      theme: CyaichiTheme.dark,
      darkTheme: CyaichiTheme.dark,
      themeMode: ThemeMode.dark,
      home: const FlowCanvasScreen(),
    );
  }
}
