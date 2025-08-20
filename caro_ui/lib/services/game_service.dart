// caro_ui/lib/services/game_service.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'network_service.dart';
import '../models/player_model.dart';
import '../models/chat_message_model.dart';
import '../models/move_model.dart';
import '../models/room_info_model.dart';
import '../game_theme.dart';

class GameService with ChangeNotifier {
  final NetworkService _networkService = NetworkService();
  StreamSubscription? _messageSubscription;

  // State
  String? _roomId;
  String? _sessionToken;
  int? _myPlayerId;
  String? _myPlayerName;
  List<Player> _players = [];
  List<Move> _moves = [];
  int? _currentPlayerId;
  bool _isGameStarted = false;
  int _boardSize = 25;
  int? _winnerId;
  bool _isDraw = false;
  bool _shouldNavigateHome = false;
  bool _hasUnreadMessages = false; // Biến cờ hiệu
  bool _shouldReturnToLobby = false;
  bool _isSessionFromReconnect = false;
  bool _justFinishedGame = false;
  final Set<int> _surrenderedPlayerIds =
      {}; // <<< THÊM MỚI: Theo dõi người chơi đã đầu hàng
  List<ChatMessage> _chatMessages = [];

  List<RoomInfo> _availableRooms = [];
  // Getters
  String? get roomId => _roomId;
  List<Player> get players => _players;
  List<Move> get moves => _moves;
  int? get currentPlayerId => _currentPlayerId;
  bool get isGameStarted => _isGameStarted;
  int get boardSize => _boardSize;
  int? get myPlayerId => _myPlayerId;
  String? get myPlayerName => _myPlayerName;
  int? get winnerId => _winnerId;
  bool get isDraw => _isDraw;
  bool get shouldReturnToLobby => _shouldReturnToLobby;
  bool get hasUnreadMessages => _hasUnreadMessages;
  bool get shouldNavigateHome => _shouldNavigateHome;
  Set<int> get surrenderedPlayerIds => _surrenderedPlayerIds; // <<< THÊM MỚI
  List<RoomInfo> get availableRooms => _availableRooms;
  List<ChatMessage> get chatMessages => _chatMessages;

  GameService() {
    _messageSubscription = _networkService.messages.listen(
      _handleServerMessage,
    );
  }
  void _resetRoomState() {
    // ================= THÊM DÒNG NÀY =================
    print("DEBUG: !!! EXECUTING _resetRoomState. Kicking user to home.");
    // ================================================
    _roomId = null;
    _sessionToken = null;
    _myPlayerId = null;
    // Không reset _myPlayerName để tiện cho việc vào phòng mới
    _players = [];
    _moves = [];
    _currentPlayerId = null;
    _isGameStarted = false;
    _winnerId = null;
    _isDraw = false;
    _shouldReturnToLobby = false;
    _isSessionFromReconnect = false;
    _surrenderedPlayerIds.clear();
    _chatMessages.clear();
  }

  void resetStateForNewConnection() {
    _resetRoomState();
    _myPlayerName = null; // Reset cả tên khi là một kết nối hoàn toàn mới
  }

  void consumeNavigateHomeSignal() {
    if (_shouldNavigateHome) {
      _shouldNavigateHome = false;
      // Không cần notifyListeners() ở đây vì việc điều hướng đã xảy ra,
      // không cần build lại UI chỉ để thay đổi cờ này.
    }
  }

  void consumeReturnToLobbySignal() {
    _shouldReturnToLobby = false;
  }

  void _updateSelfInfoAndSaveSession(List<Player> newPlayerList) {
    // ================= THÊM DÒNG NÀY =================
    print("DEBUG: ==> Entering _updateSelfInfoAndSaveSession...");
    // ================================================
    try {
      Player? myPlayer;

      // Ưu tiên tìm bằng ID nếu _myPlayerId đã tồn tại và hợp lệ.
      // Đây là cách xác định đáng tin cậy nhất sau khi đã vào phòng hoặc reconnect.
      if (_myPlayerId != null) {
        try {
          myPlayer = newPlayerList.firstWhere((p) => p.playerId == _myPlayerId);
          // ================= THÊM DÒNG NÀY =================
          print(
            "DEBUG: Find player SUCCESS - ID=${myPlayer.playerId}, Name=${myPlayer.playerName}",
          );
          //
        } catch (e) {
          // ================= THÊM DÒNG NÀY =================
          print(
            "DEBUG: !!! CATCH ERROR in _updateSelfInfoAndSaveSession. Player possibly kicked.",
          );
          // ================================================
          // Không tìm thấy bằng ID, có thể có trường hợp đặc biệt, thử tìm bằng tên
          print(
            "Không tìm thấy người chơi bằng ID ${_myPlayerId}, thử tìm bằng tên.",
          );
          myPlayer = null;
        }
      }

      //
      // Nếu không tìm thấy bằng ID (hoặc _myPlayerId ban đầu là null), thử tìm bằng tên.
      // Trường hợp này thường xảy ra khi vừa mới join phòng và chưa có ID rõ ràng.
      if (myPlayer == null) {
        myPlayer = newPlayerList.firstWhere(
          (p) => p.playerName == _myPlayerName,
        );
      }

      // Cập nhật thông tin từ đối tượng Player đã tìm thấy
      _myPlayerId = myPlayer.playerId;
      _myPlayerName =
          myPlayer.playerName; // Cập nhật lại tên từ server để đảm bảo đồng bộ
      _sessionToken = myPlayer.sessionToken; // Cập nhật session token mới nhất

      print(
        "Đã cập nhật thông tin người chơi: ID=${_myPlayerId}, Name=${_myPlayerName}, Token=${_sessionToken}",
      );

      // Lưu lại session mới nhất để đảm bảo reconnect luôn đúng
      _saveSessionInfo();
    } catch (e) {
      print(
        "Cảnh báo nghiêm trọng: Không thể tìm thấy người chơi '${_myPlayerName}' (ID: ${_myPlayerId}) trong danh sách. Bạn có thể đã bị kick.",
      );
      _resetRoomState();
      _shouldNavigateHome = true;
      clearSavedSession();
    }
  }

  void _handleServerMessage(Map<String, dynamic> message) {
    final type = message['Type'] as String;
    final payload = message['Payload'] as Map<String, dynamic>? ?? {};
    // ================= THÊM DÒNG NÀY =================
    print("DEBUG: ReceivedFromServer -> Type: $type, Payload: $payload");
    // ================================================
    switch (type) {
      case 'GAME_START':
        _isGameStarted = true;
        _moves.clear();
        _isSessionFromReconnect = false;
        _justFinishedGame = false;
        _winnerId = null;

        _isDraw = false;
        _surrenderedPlayerIds.clear();
        _currentPlayerId = payload['StartingPlayerId'];
        _boardSize = payload['BoardSize'] as int;
        final playerList = payload['Players'] as List;
        _players =
            playerList
                .map((p) => Player.fromJson(p as Map<String, dynamic>))
                .toList();
        _updateSelfInfoAndSaveSession(_players);

        print("Trận đấu bắt đầu! My Player ID is: $_myPlayerId");
        break;
      case 'ROOM_LIST_UPDATE':
        final roomsList = payload['Rooms'] as List;
        _availableRooms =
            roomsList.map((roomJson) {
              return RoomInfo.fromJson(roomJson as Map<String, dynamic>);
            }).toList();
        break;
      // <<< THÊM MỚI: Xử lý khi có người chơi đầu hàng
      case 'PLAYER_SURRENDERED':
        final playerId = payload['PlayerId'] as int?;
        _isSessionFromReconnect = false;
        if (playerId != null) {
          _surrenderedPlayerIds.add(playerId);
        }
        break;
      case 'RETURN_TO_LOBBY':
        print("Nhận tín hiệu RETURN_TO_LOBBY từ server.");
        _isGameStarted = false;
        _moves.clear();
        _winnerId = null;
        _isDraw = false;
        _isSessionFromReconnect = false;
        _currentPlayerId = null;
        _surrenderedPlayerIds.clear();

        if (payload.containsKey('Players')) {
          final playerList = payload['Players'] as List;
          _players =
              playerList
                  .map((p) => Player.fromJson(p as Map<String, dynamic>))
                  .toList();

          // SỬA LỖI: Cập nhật lại thông tin và lưu session mới

          _updateSelfInfoAndSaveSession(_players);
        } else {
          print(
            "Cảnh báo: Tin nhắn RETURN_TO_LOBBY không chứa danh sách người chơi.",
          );
        }
        _shouldReturnToLobby = true;
        break;
      case 'GAME_OVER':
        _isDraw = payload['IsDraw'] as bool? ?? false;
        if (!_isDraw) {
          _winnerId = payload['WinnerId'] as int?;
        }

        clearSavedSession();

        _justFinishedGame = true;
        print("Game Over! WinnerId: $_winnerId, IsDraw: $_isDraw");
        break;
      case 'LEAVE_ROOM_SUCCESS': // Bạn đã thoát phòng thành công [cite: 35]
      case 'ROOM_CLOSED': // Chủ phòng thoát, phòng bị đóng [cite: 43]
        _roomId = null;
        _players = [];
        _isGameStarted = false;
        _moves = [];
        _chatMessages = [];
        clearSavedSession();
        // Không set _shouldNavigateHome = true nữa
        break;

      case 'ROOM_CREATED':
        _roomId = payload['RoomId'];
        _sessionToken = payload['SessionToken'];
        _isSessionFromReconnect = false;
        _myPlayerId = 0;
        _chatMessages.clear();
        _players = [
          Player(
            playerId: 0,
            playerName: _myPlayerName ?? "Bạn",
            color: AppColors.playerColors[0],
            isHost: true,
            sessionToken: _sessionToken,
          ),
        ];
        _saveSessionInfo();
        break;
      case 'JOIN_RESULT':
        if (payload['Success'] == true) {
          _roomId = payload['RoomId'];
          _sessionToken = payload['SessionToken'];
          _isSessionFromReconnect = false;
          final playerList = payload['Players'] as List;
          _chatMessages.clear();
          _players =
              playerList
                  .map((p) => Player.fromJson(p as Map<String, dynamic>))
                  .toList();
          if (!_players.any((p) => p.playerName == _myPlayerName)) {
            final myId = _players.length;
            _myPlayerId = myId;
            _players.add(
              Player(
                playerName: _myPlayerName!,
                playerId: myId,
                color: AppColors.playerColors[myId % 4],
                isHost: false,
              ),
            );
          }
          _saveSessionInfo();
        }
        break;
      case 'PLAYER_JOINED':
        final newPlayer = Player.fromJson(payload);
        if (!_players.any((p) => p.playerId == newPlayer.playerId)) {
          _players.add(newPlayer);
        }
        break;
      case 'CHAT_MESSAGE_RECEIVED':
        final newChatMessage = ChatMessage.fromJson(payload);
        _chatMessages.add(newChatMessage);
        final chatPayload = payload as Map<String, dynamic>;
        final senderId = chatPayload['PlayerId'] as int?;
        if (senderId != null && senderId != _myPlayerId) {
          _hasUnreadMessages = true;
        }
        break;
      case 'GAME_STATE_UPDATE':
        // ... (xử lý Players, Moves,...)
        if (payload.containsKey('ChatHistory')) {
          final chatHistoryList = payload['ChatHistory'] as List;
          _chatMessages =
              chatHistoryList
                  .map(
                    (chat) =>
                        ChatMessage.fromJson(chat as Map<String, dynamic>),
                  )
                  .toList();
        }
        break;
      case 'BOARD_UPDATE':
        final newMove = Move(
          x: payload['X'],
          y: payload['Y'],
          playerId: payload['PlayerId'],
        );
        _moves.add(newMove);
        break;
      case 'TURN_UPDATE':
        _currentPlayerId = payload['NextPlayerId'];
        break;

      case 'RECONNECT_RESULT':
        if (payload['Success'] == true) {
          print("Kết nối lại thành công! Đang khôi phục trạng thái...");
          _isSessionFromReconnect = true;
          final gameState = payload['GameState'] as Map<String, dynamic>;
          _restoreGameState(gameState);
        } else {
          print("Kết nối lại thất bại. Xóa session cũ.");
          clearSavedSession();
          _resetRoomState(); // Reset trạng thái để không bị lẫn lộn
          _shouldNavigateHome = true;
          // (Tùy chọn) Có thể thêm logic hiển thị thông báo lỗi cho người dùng ở đây
        }
        break;

      case 'PLAYER_DISCONNECTED':
        final playerId = payload['PlayerId'] as int;
        print("Người chơi $playerId đã mất kết nối.");
        // (Sẽ thêm logic cập nhật UI ở bước sau)
        break;

      case 'PLAYER_RECONNECTED':
        final playerId = payload['PlayerId'] as int;
        print("Người chơi $playerId đã kết nối lại.");
        // (Sẽ thêm logic cập nhật UI ở bước sau)
        break;
    }
    notifyListeners();
  }

  void createRoom(String playerName) {
    _myPlayerName = playerName;
    _networkService.send('CREATE_ROOM', {'PlayerName': playerName});
  }

  void joinRoom(String roomId, String playerName) {
    _myPlayerName = playerName;
    _networkService.send('JOIN_ROOM', {
      'PlayerName': playerName,
      'RoomId': roomId,
    });
  }

  void makeMove(int x, int y) {
    if (_currentPlayerId == _myPlayerId && _isGameStarted) {
      _networkService.send('MAKE_MOVE', {'X': x, 'Y': y});
    }
  }

  void getRoomList() {
    _networkService.send('GET_ROOM_LIST', {});
  }

  void setMyPlayerName(String name) {
    _myPlayerName = name;
    _saveLastPlayerName(name);
  }

  void surrender() {
    if (_isGameStarted) {
      _networkService.send('SURRENDER', {});
    }
  }

  void markChatAsRead() {
    if (_hasUnreadMessages) {
      _hasUnreadMessages = false;
      notifyListeners(); // Thông báo cho UI cập nhật (để xóa chấm đỏ)
    }
  }

  void findMatch(String playerName) {
    // 1. Lưu lại tên người chơi
    setMyPlayerName(playerName);
    // 2. Gửi yêu cầu FIND_MATCH lên server
    _networkService.send('FIND_MATCH', {'PlayerName': playerName});
  }

  void leaveRoom() {
    if (_roomId != null) {
      _networkService.send('LEAVE_ROOM', {});
    }
  }

  void sendChatMessage(String message) {
    if (message.trim().isNotEmpty) {
      _networkService.send('SEND_CHAT_MESSAGE', {'Message': message});
    }
  }

  void startGameEarly() {
    if (_players.any((p) => p.playerId == _myPlayerId && p.isHost)) {
      _networkService.send('START_GAME_EARLY', {});
    }
  }

  void _restoreGameState(Map<String, dynamic> gameState) {
    _isGameStarted = true;

    final playerList = gameState['Players'] as List;
    _players =
        playerList
            .map((p) => Player.fromJson(p as Map<String, dynamic>))
            .toList();

    final moveList = gameState['Moves'] as List;
    _moves =
        moveList.map((m) => Move.fromJson(m as Map<String, dynamic>)).toList();

    _currentPlayerId = gameState['CurrentPlayerId'];

    if (gameState.containsKey('ChatHistory')) {
      final chatHistoryList = gameState['ChatHistory'] as List;
      _chatMessages =
          chatHistoryList
              .map((chat) => ChatMessage.fromJson(chat as Map<String, dynamic>))
              .toList();
    }

    try {
      final myPlayerInfo = _players.firstWhere(
        (p) => p.playerName == _myPlayerName, // Thay đổi điều kiện tìm kiếm
      );
      _myPlayerId = myPlayerInfo.playerId;
      // Tên có thể không thay đổi, nhưng gán lại để đảm bảo
      _myPlayerName = myPlayerInfo.playerName;
      _roomId = gameState['RoomId'];
    } catch (e) {
      print(
        "LỖI NGHIÊM TRỌNG: Không thể tìm thấy người chơi '${_myPlayerName}' khi khôi phục trạng thái.",
      );
      // Nếu không tìm thấy, reset trạng thái để tránh lỗi
      _resetRoomState();
      _shouldNavigateHome = true;
    }
  }

  Future<void> _saveSessionInfo() async {
    if (_roomId != null && _sessionToken != null && _myPlayerName != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('roomId', _roomId!);
      await prefs.setString('sessionToken', _sessionToken!);
      await prefs.setString('playerName', _myPlayerName!);
      print(
        "Đã lưu thông tin ván đấu: RoomId=$_roomId, PlayerName=$_myPlayerName",
      );
    }
  }

  // THÊM MỚI: Hàm lưu tên người chơi cuối cùng
  Future<void> _saveLastPlayerName(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastPlayerName', name);
    } catch (e) {
      print("Lỗi khi lưu tên người chơi: $e");
    }
  }

  // THÊM MỚI: Hàm tải tên người chơi cuối cùng
  Future<String?> loadLastPlayerName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('lastPlayerName');
    } catch (e) {
      print("Lỗi khi tải tên người chơi: $e");
      return null;
    }
  }

  Future<Map<String, String>?> loadSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final roomId = prefs.getString('roomId');
    final sessionToken = prefs.getString('sessionToken');
    final playerName = prefs.getString('playerName');

    if (roomId != null && sessionToken != null && playerName != null) {
      return {
        'roomId': roomId,
        'sessionToken': sessionToken,
        'playerName': playerName,
      };
    }
    return null;
  }

  Future<void> clearSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('roomId');
    await prefs.remove('sessionToken');
    await prefs.remove('playerName');
    print("Đã xóa thông tin ván đấu cũ.");
  }

  void reconnectToSavedGame(
    String roomId,
    String sessionToken,
    String playerName,
  ) {
    // Gán lại thông tin để service có thể xác định người chơi sau khi khôi phục
    _roomId = roomId;
    _sessionToken = sessionToken;
    _myPlayerName = playerName;
    _networkService.send('RECONNECT', {
      'RoomId': roomId,
      'SessionToken': sessionToken,
    });
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }
}
