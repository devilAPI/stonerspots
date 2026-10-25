ALTER TABLE spots DROP COLUMN locked;
ALTER TABLE spot_tags DROP FOREIGN KEY fk_spot_tags_tag;
DROP TABLE tags;
