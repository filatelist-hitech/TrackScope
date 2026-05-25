import 'package:flutter/material.dart';

void main() {
  runApp(const HitechBpmRadarApp());
}

class HitechBpmRadarApp extends StatelessWidget {
  const HitechBpmRadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'hitech-bpm-radar',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff00a884)),
        useMaterial3: true,
      ),
      home: const DspContractGateScreen(),
    );
  }
}

class DspContractGateScreen extends StatelessWidget {
  const DspContractGateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('hitech-bpm-radar')),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DSP contract ready',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 12),
              Text(
                'Microphone capture and live BPM rendering are blocked until the Rust FFI bridge emits verified DspResult snapshots.',
              ),
              SizedBox(height: 24),
              _ContractRow(label: 'Primary BPM', value: 'null until trusted'),
              _ContractRow(label: 'Confidence', value: '0.0-1.0'),
              _ContractRow(label: 'Lock state', value: 'SEARCHING'),
              _ContractRow(label: 'Candidates', value: 'visible in debug mode'),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContractRow extends StatelessWidget {
  const _ContractRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
