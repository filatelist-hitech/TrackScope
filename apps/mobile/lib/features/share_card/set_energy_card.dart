import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../setlist/setlist_entry.dart';
import 'set_energy_card_painter.dart';

/// Off-screen widget that renders the set-energy card and exposes [captureAndShare].
///
/// Place this in an [Offstage] wrapper so it participates in the render tree
/// (required for [RenderRepaintBoundary.toImage]) without being visible.
class SetEnergyCard extends StatefulWidget {
  const SetEnergyCard({super.key, required this.entries});

  final List<SetlistEntry> entries;

  @override
  State<SetEnergyCard> createState() => SetEnergyCardState();
}

class SetEnergyCardState extends State<SetEnergyCard> {
  final _key = GlobalKey();

  static const double _cardSize = 1080.0;

  /// Renders the card to PNG and shares it via share_plus.
  Future<void> captureAndShare() async {
    final boundary =
        _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;

    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;

    final pngBytes = byteData.buffer.asUint8List();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/trackscope_set_card.png');
    await file.writeAsBytes(pngBytes);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png')],
      subject: 'TrackScope Set Card',
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _key,
      child: CustomPaint(
        painter: SetEnergyCardPainter(widget.entries),
        size: const Size(_cardSize, _cardSize),
      ),
    );
  }
}
