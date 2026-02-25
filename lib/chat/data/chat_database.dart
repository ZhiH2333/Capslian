import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'models/local_chat_message.dart';

/// 聊天本地数据库，基于 SQLite（sqflite）。
/// 存储聊天房间消息，支持离线与首屏加速。
class ChatDatabase {
  ChatDatabase._();

  static Database? _db;
  static const int _version = 1;
  static const String _messagesTable = 'chat_room_messages';

  static Future<Database> _getDb() async {
    if (_db != null && _db!.isOpen) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'molian_chat_rooms.db');
    _db = await openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
    );
    return _db!;
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_messagesTable (
        id TEXT PRIMARY KEY,
        room_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'sent',
        created_at TEXT,
        updated_at TEXT,
        deleted_at TEXT,
        nonce TEXT,
        attachments_json TEXT,
        reply_message_id TEXT,
        forwarded_message_id TEXT,
        reactions_json TEXT,
        meta_json TEXT,
        sender_json TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_chat_room_messages_room ON $_messagesTable (room_id, created_at)',
    );
    await db.execute(
      'CREATE INDEX idx_chat_room_messages_nonce ON $_messagesTable (nonce)',
    );
  }

  /// 保存或替换单条消息（含发送者信息）。
  static Future<void> saveMessage(LocalChatMessage message) async {
    final db = await _getDb();
    await db.insert(
      _messagesTable,
      message.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 删除指定 id 的消息。
  static Future<void> deleteMessage(String id) async {
    final db = await _getDb();
    await db.delete(_messagesTable, where: 'id = ?', whereArgs: [id]);
  }

  /// 按房间获取消息列表，支持分页（offset + take），按 created_at 升序。
  static Future<List<LocalChatMessage>> getMessagesForRoom(
    String roomId, {
    int offset = 0,
    int take = 50,
  }) async {
    final db = await _getDb();
    final rows = await db.query(
      _messagesTable,
      where: 'room_id = ?',
      whereArgs: [roomId],
      orderBy: 'created_at ASC',
      limit: take,
      offset: offset,
    );
    return rows.map(LocalChatMessage.fromDbMap).toList();
  }

  /// 按 id 获取单条消息。
  static Future<LocalChatMessage?> getMessageById(String id) async {
    final db = await _getDb();
    final rows = await db.query(
      _messagesTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LocalChatMessage.fromDbMap(rows.first);
  }

  /// 按 nonce 获取消息（用于 pending 消息去重）。
  static Future<LocalChatMessage?> getMessageByNonce(String nonce) async {
    final db = await _getDb();
    final rows = await db.query(
      _messagesTable,
      where: 'nonce = ?',
      whereArgs: [nonce],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LocalChatMessage.fromDbMap(rows.first);
  }

  /// 更新消息状态。
  static Future<void> updateMessageStatus(
    String id,
    MessageStatus status,
  ) async {
    final db = await _getDb();
    await db.update(
      _messagesTable,
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 批量保存消息。
  static Future<void> saveMessages(List<LocalChatMessage> messages) async {
    if (messages.isEmpty) return;
    final db = await _getDb();
    final batch = db.batch();
    for (final m in messages) {
      batch.insert(
        _messagesTable,
        m.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}
