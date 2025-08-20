// caro_ui/lib/models/player_model.dart

import 'package:flutter/material.dart';
import '../game_theme.dart';

class Player {
  final String playerName;
  final int playerId;
  final bool isHost;
  final Color color;
  // THÊM MỚI: Thêm trường sessionToken
  final String? sessionToken;

  Player({
    required this.playerName,
    required this.playerId,
    required this.color,
    this.isHost = false,
    this.sessionToken, // Thêm vào constructor
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    int id = json['PlayerId'] as int;
    return Player(
      playerName: json['PlayerName'] as String,
      playerId: id,
      isHost: json['IsHost'] as bool? ?? false,
      color: AppColors.playerColors[id % AppColors.playerColors.length],
      // THÊM MỚI: Đọc sessionToken từ JSON (nếu có)
      sessionToken: json['SessionToken'] as String?,
    );
  }
}
