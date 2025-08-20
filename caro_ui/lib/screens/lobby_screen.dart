// File: caro_ui/lib/screens/lobby_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:caro_ui/services/connection_screen.dart';
import '../game_theme.dart';
import '../models/player_model.dart';
import '../services/game_service.dart';
import '../widgets/chat_drawer.dart';
import 'game_screen.dart';
import 'room_list_screen.dart';

class LobbyScreen extends StatefulWidget {
  LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _roomIdController = TextEditingController();
  @override
  void initState() {
    super.initState();

    _loadInitialPlayerName();
    // THÊM MỚI: Kiểm tra ván đấu đã lưu ngay khi màn hình được tải
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkForSavedGame();
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _roomIdController.dispose();
    super.dispose();
  }

  void _loadInitialPlayerName() async {
    final gameService = context.read<GameService>();
    final savedName = await gameService.loadLastPlayerName();
    if (savedName != null && savedName.isNotEmpty && mounted) {
      setState(() {
        _nameController.text = savedName;
      });
      // Đặt tên sẵn cho service để dùng ngay
      gameService.setMyPlayerName(savedName);
    }
  }

  void _handlePlayerAction(Function(String playerName) action) {
    final playerName = _nameController.text.trim();
    if (playerName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập tên người chơi của bạn trước.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } else {
      // Lưu tên vào service để các hàm khác có thể sử dụng
      context.read<GameService>().setMyPlayerName(playerName);
      // Thực hiện hành động cụ thể (tạo phòng, tìm trận, etc.)
      action(playerName);
    }
  }

  void _checkForSavedGame() async {
    final gameService = context.read<GameService>();
    final session = await gameService.loadSavedSession();

    if (session != null && mounted) {
      final playerName = session['playerName']!;
      // Cập nhật lại tên người chơi trên UI
      _nameController.text = playerName;
      gameService.setMyPlayerName(playerName);

      showDialog(
        context: context,
        barrierDismissible: false, // Người dùng bắt buộc phải chọn
        builder:
            (context) => AlertDialog(
              backgroundColor: AppColors.parchment,
              title: const Text("Phát hiện ván đấu cũ"),
              content: Text(
                "Bạn có muốn tham gia lại ván đấu của '${playerName}' không?",
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    gameService.clearSavedSession();
                    //gameService.leaveRoom();

                    Navigator.of(context).pop();
                  },
                  child: const Text(
                    "Bỏ qua",
                    style: TextStyle(color: AppColors.ink),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    gameService.reconnectToSavedGame(
                      session['roomId']!,
                      session['sessionToken']!,
                      playerName,
                    );
                    Navigator.of(context).pop();
                  },
                  child: const Text("Tham gia lại"),
                ),
              ],
            ),
      );
    }
  }

  void _showJoinRoomDialog(BuildContext context) {
    final gameService = context.read<GameService>();
    final roomIdController = TextEditingController();
    final playerName = gameService.myPlayerName!;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: AppColors.parchment,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Bọc TextField và các nút trong một Row
                  Row(
                    children: [
                      // Dùng Expanded để TextField chiếm hết không gian còn lại
                      Expanded(
                        child: TextField(
                          controller: roomIdController,
                          decoration: const InputDecoration(
                            labelText: "Nhập mã phòng...",
                            border: OutlineInputBorder(),
                          ),
                          autofocus: true,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(
                        width: 8,
                      ), // Khoảng cách giữa TextField và nút
                      ElevatedButton(
                        onPressed: () {
                          final roomId =
                              roomIdController.text.trim().toUpperCase();
                          if (roomId.isNotEmpty) {
                            gameService.joinRoom(roomId, playerName);
                            Navigator.of(context).pop();
                          }
                        },
                        child: const Text("Tham gia"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Nút Hủy có thể đặt riêng ở đây hoặc trong Row trên
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      "Hủy",
                      style: TextStyle(color: AppColors.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final gameService = context.watch<GameService>();

    if (gameService.isGameStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ModalRoute.of(context)?.settings.name != '/game' && mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const GameScreen(),
              settings: const RouteSettings(name: '/game'),
            ),
          );
        }
      });
      return const Scaffold(
        backgroundColor: AppColors.parchment,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (gameService.shouldNavigateHome) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          gameService.consumeNavigateHomeSignal();
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const ConnectionScreen()),
            (Route<dynamic> route) => false,
          );
        }
      });
      return const Scaffold(
        backgroundColor: AppColors.parchment,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final bool isInLobby = gameService.roomId != null;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.parchment,
      appBar: AppBar(
        backgroundColor: AppColors.woodFrame,
        elevation: 4,
        title: Text(
          isInLobby ? 'Phòng Chờ' : 'Trang Chủ',
          style: textTheme.headlineSmall?.copyWith(color: AppColors.parchment),
        ),
        automaticallyImplyLeading: false,
        actions: [
          // Chỉ hiển thị nút này khi chưa ở trong phòng chờ nào
          if (!isInLobby)
            IconButton(
              icon: const Icon(Icons.menu_open),
              tooltip: 'Danh sách phòng',
              onPressed:
                  () => _handlePlayerAction((playerName) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const RoomListScreen(),
                      ),
                    );
                  }),
            ),
        ],
      ),
      endDrawer: const ChatDrawer(),
      body: isInLobby ? _buildLobbyView(context) : _buildInitialView(context),
    );
  }

  Widget _buildInitialView(BuildContext context) {
    final gameService = context.read<GameService>();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Chào mừng tới Caro Online!",
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: "Tên người chơi",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            // SỬA LỖI: Bọc các nút trong Wrap để xuống dòng khi không đủ chỗ
            Wrap(
              spacing: 16,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton(
                  onPressed:
                      () => _handlePlayerAction((playerName) {
                        gameService.createRoom(playerName);
                      }),
                  child: const Text('Tạo Phòng Mới'),
                ),
                // THÊM MỚI: Nút Tìm trận
                ElevatedButton(
                  onPressed:
                      () => _handlePlayerAction((playerName) {
                        gameService.findMatch(playerName);
                      }),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.highlight, // Màu xanh lá
                  ),
                  child: const Text('Tìm trận'),
                ),
                OutlinedButton(
                  onPressed:
                      () => _handlePlayerAction((playerName) {
                        _showJoinRoomDialog(context);
                      }),
                  child: const Text('Tham gia phòng'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLobbyView(BuildContext context) {
    // --- THAY ĐỔI: Bọc cột trái trong SingleChildScrollView ---
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              // <--- Bọc ở đây
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildRoomInfoCard(context),
                  const SizedBox(height: 24),
                  const _LobbyActionButtons(),
                ],
              ),
            ),
          ),
          const VerticalDivider(
            color: AppColors.woodFrame,
            thickness: 2,
            indent: 20,
            endIndent: 20,
          ),
          Expanded(flex: 3, child: _buildPlayerList(context)),
        ],
      ),
    );
  }

  Widget _buildRoomInfoCard(BuildContext context) {
    final gameService = context.watch<GameService>();
    return Card(
      color: AppColors.parchment,
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Column(
              children: [
                const Text("MÃ PHÒNG", style: TextStyle(color: Colors.grey)),
                Text(
                  gameService.roomId!,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: gameService.roomId!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã sao chép mã phòng!')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerList(BuildContext context) {
    final gameService = context.watch<GameService>();
    final players = gameService.players;
    return Column(
      children: [
        Text(
          "NGƯỜI CHƠI (${players.length}/4)",
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const Divider(),
        Expanded(
          child:
              players.isEmpty
                  ? const Center(child: Text("Chưa có ai trong phòng."))
                  : ListView.builder(
                    itemCount: players.length,
                    itemBuilder: (context, index) {
                      final player = players[index];
                      return Card(
                        color: AppColors.parchment.withOpacity(0.7),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: player.color,
                            child: Text('${player.playerId + 1}'),
                          ),
                          title: Text(
                            player.playerName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          trailing:
                              player.isHost
                                  ? const Icon(
                                    Icons.star,
                                    color: AppColors.highlight,
                                  )
                                  : null,
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}

class _LobbyActionButtons extends StatelessWidget {
  const _LobbyActionButtons();

  @override
  Widget build(BuildContext context) {
    final gameService = context.watch<GameService>();
    final isHost = gameService.myPlayerId == 0;
    final players = gameService.players;

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12.0,
      runSpacing: 12.0,
      direction: Axis.vertical,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text("Trò chuyện"),
              onPressed: () {
                // BƯỚC 3: Đánh dấu đã đọc tin nhắn
                context.read<GameService>().markChatAsRead();
                // Mở ngăn kéo chat
                Scaffold.of(context).openEndDrawer();
              },
            ),
            // BƯỚC 2: Hiển thị chấm đỏ nếu có tin nhắn chưa đọc
            if (gameService.hasUnreadMessages)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.parchment, width: 2),
                  ),
                ),
              ),
          ],
        ),
        if (isHost && players.length >= 2)
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text("Bắt đầu"),
            onPressed: () => gameService.startGameEarly(),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
        ElevatedButton.icon(
          icon: const Icon(Icons.exit_to_app),
          label: const Text("Rời phòng"),
          onPressed: () => gameService.leaveRoom(),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
        ),
      ],
    );
  }
}
