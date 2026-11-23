import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../core/ui/redesign_widgets.dart';
import '../data/medication_setup_repository.dart';

/// Optional private photo, with the usual medication artwork as fallback.
class MedicationArtwork extends StatelessWidget {
  const MedicationArtwork({super.key, required this.name,
    this.setup, this.size = 54});

  final String name;
  final MedicationSetup? setup;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = MedicineArtwork(
      seed: '${setup?.artwork ?? 'capsule'}:$name', size: size);
    final path = setup?.localImagePath;
    if (path == null || path.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .23),
      child: Image.file(File(path), width: size, height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback),
    );
  }
}
