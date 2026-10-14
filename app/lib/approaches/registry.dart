import 'package:flutter/material.dart';

import '../core/check.dart';
import '../screens/photo_check_screen.dart';
import 'a01_face_detection/face_detection_check.dart';
import 'a02_zero_shot/zero_shot_check.dart';
import 'a03_capture_integrity/capture_integrity_check.dart';
import 'a04_forensics/forensics_check.dart';
import 'a05_active_liveness/active_liveness_screen.dart';
import 'server/server_check.dart';

/// One tile on the home grid.
class ApproachTile {
  const ApproachTile({
    required this.id,
    required this.title,
    required this.summary,
    required this.catches,
    required this.icon,
    required this.open,
  });

  final String id;
  final String title;
  final String summary;

  /// Fake types (plan.md §1) this approach is expected to catch.
  final List<String> catches;
  final IconData icon;
  final Widget Function() open;
}

Widget _photo(PhotoCheck Function() make) => PhotoCheckScreen(check: make());

/// Tier 1: no training, runs on the phone (plan.md §5).
final tier1 = <ApproachTile>[
  ApproachTile(
    id: '01',
    title: 'Face detection',
    summary: 'One clear, frontal face?',
    catches: ['F1 no human'],
    icon: Icons.face_retouching_natural,
    open: () => _photo(FaceDetectionCheck.new),
  ),
  ApproachTile(
    id: '02',
    title: 'Zero-shot',
    summary: 'Person, scene, screen, cartoon?',
    catches: ['F1', 'F5 not real', 'F2/F3 partly'],
    icon: Icons.manage_search,
    open: () => _photo(ZeroShotCheck.new),
  ),
  ApproachTile(
    id: '03',
    title: 'Capture integrity',
    summary: 'Live, fresh, real phone, real GPS?',
    catches: ['F3 gallery/screenshot'],
    icon: Icons.verified_user_outlined,
    open: () => _photo(CaptureIntegrityCheck.new),
  ),
  ApproachTile(
    id: '04',
    title: 'Recapture forensics',
    summary: 'Moiré, glare, blur, metadata',
    catches: ['F2 partly', 'F3'],
    icon: Icons.grain,
    open: () => _photo(ForensicsCheck.new),
  ),
  ApproachTile(
    id: '05',
    title: 'Active liveness',
    summary: 'Blink and turn on request',
    catches: ['F2 prints/screens', 'F1', 'F3'],
    icon: Icons.visibility,
    open: ActiveLivenessScreen.new,
  ),
];

/// Tier 2: no training, runs on the HumanDetect server (server/README.md).
final tier2 = <ApproachTile>[
  ApproachTile(
    id: '06',
    title: 'Zero-shot detection',
    summary: 'Face found, and not on a screen or a painting?',
    catches: ['F1', 'F2 partly', 'F5 partly'],
    icon: Icons.travel_explore,
    open: () => _photo(serverChecks['06']!),
  ),
  ApproachTile(
    id: '07',
    title: 'Duplicate detection',
    summary: 'Has this photo been submitted before?',
    catches: ['F4 reused photo'],
    icon: Icons.content_copy,
    open: () => _photo(serverChecks['07']!),
  ),
  ApproachTile(
    id: '08',
    title: 'Deep detectors',
    summary: 'One clear person, not on a screen?',
    catches: ['F1', 'F2 partly'],
    icon: Icons.person_search,
    open: () => _photo(serverChecks['08']!),
  ),
  ApproachTile(
    id: '09',
    title: 'Open VLM judge',
    summary: 'A small open model answers: what is this?',
    catches: ['F1', 'F2', 'F5'],
    icon: Icons.psychology_alt,
    open: () => _photo(serverChecks['09']!),
  ),
];
