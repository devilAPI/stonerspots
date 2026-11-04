DELETE FROM reports WHERE target_type = 'comment';
ALTER TABLE reports MODIFY target_type ENUM('spot','update','review') NOT NULL;
DROP TABLE IF EXISTS comments;
