// caro_ui/lib/models/move_model.dart

class Move {
  final int x;
  final int y;
  final int playerId;

  Move({required this.x, required this.y, required this.playerId});

  // THÊM MỚI: Factory constructor để tạo Move từ JSON
  factory Move.fromJson(Map<String, dynamic> json) {
    return Move(
      x: json['X'] as int,
      y: json['Y'] as int,
      playerId: json['PlayerId'] as int,
    );
  }
}
