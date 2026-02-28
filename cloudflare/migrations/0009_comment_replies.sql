-- 评论支持回复：parent_id 指向被回复的评论
ALTER TABLE comments ADD COLUMN parent_id TEXT REFERENCES comments(id);

CREATE INDEX IF NOT EXISTS idx_comments_parent ON comments(parent_id);
