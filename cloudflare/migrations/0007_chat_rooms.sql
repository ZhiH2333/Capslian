-- 聊天房间表
CREATE TABLE IF NOT EXISTS chat_rooms (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'direct',
  description TEXT,
  avatar_url TEXT,
  member_count INTEGER DEFAULT 0,
  last_message_at TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

-- 房间成员表
CREATE TABLE IF NOT EXISTS chat_room_members (
  id TEXT PRIMARY KEY,
  room_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'member',
  joined_at TEXT DEFAULT (datetime('now')),
  UNIQUE(room_id, user_id)
);

-- 房间消息表
CREATE TABLE IF NOT EXISTS chat_room_messages (
  id TEXT PRIMARY KEY,
  room_id TEXT NOT NULL,
  sender_id TEXT NOT NULL,
  content TEXT NOT NULL DEFAULT '',
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  deleted_at TEXT,
  nonce TEXT,
  reply_id TEXT,
  forwarded_id TEXT,
  attachments TEXT NOT NULL DEFAULT '[]',
  reactions TEXT NOT NULL DEFAULT '{}',
  meta TEXT
);

CREATE INDEX IF NOT EXISTS idx_chat_room_messages_room ON chat_room_messages (room_id, created_at);
CREATE INDEX IF NOT EXISTS idx_chat_room_messages_nonce ON chat_room_messages (nonce);
