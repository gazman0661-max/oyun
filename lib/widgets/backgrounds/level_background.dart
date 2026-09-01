import 'dart:math';

import 'package:flutter/material.dart';

import 'meteor_shower_background.dart';
import 'solar_system_background.dart';
import 'spaceships_background.dart';
import 'ufos_background.dart';

/// Her bolum (level) ekrani acildiginda, 4 hazir arkaplan animasyonundan
/// (meteor yagmuru, gunes sistemi, uzay gemileri, ufolar) birini RASTGELE
/// secip gosterir. Secim, bu widget'in State'i olusturuldugunda bir kez
/// yapilir ve o oturum icinde (ornegin duraklatma/devam gibi rebuild'lerde)
/// sabit kalir — boylece oyun sirasinda arkaplan aniden degismez.
class LevelBackground extends StatefulWidget {
  final Widget? child;
  const LevelBackground({super.key, this.child});

  @override
  State<LevelBackground> createState() => _LevelBackgroundState();
}

class _LevelBackgroundState extends State<LevelBackground> {
  late final int _variant;

  @override
  void initState() {
    super.initState();
    _variant = Random().nextInt(4);
  }

  @override
  Widget build(BuildContext context) {
    switch (_variant) {
      case 0:
        return MeteorShowerBackground(child: widget.child);
      case 1:
        return SolarSystemBackground(child: widget.child);
      case 2:
        return SpaceshipsBackground(child: widget.child);
      default:
        return UfosBackground(child: widget.child);
    }
  }
}
