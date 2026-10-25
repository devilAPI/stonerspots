-- Spot tags become data: admins can add, rename and remove them. The seven
-- built-in tags are seeded with their former order and names. icon is a
-- name from the app's fixed icon set (unknown names show a generic icon).
CREATE TABLE tags (
  tag VARCHAR(16) NOT NULL,
  name_de VARCHAR(40) NOT NULL,
  name_en VARCHAR(40) NOT NULL,
  icon VARCHAR(32) NOT NULL,
  sort INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (tag)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO tags (tag, name_de, name_en, icon, sort) VALUES
  ('roof', 'Überdacht', 'Roof', 'roof', 10),
  ('seating', 'Sitzgelegenheit', 'Seating', 'seating', 20),
  ('view', 'Aussicht', 'View', 'view', 30),
  ('quiet', 'Ruhig', 'Quiet', 'quiet', 40),
  ('shade', 'Schatten', 'Shade', 'shade', 50),
  ('water', 'Wasser in der Nähe', 'Water nearby', 'water', 60),
  ('lit', 'Beleuchtet', 'Lit', 'lit', 70);

-- Drop rows with tags that never existed, then tie spot_tags to the catalog:
-- deleting a tag removes it from every spot.
DELETE FROM spot_tags WHERE tag NOT IN (SELECT tag FROM tags);
ALTER TABLE spot_tags
  ADD CONSTRAINT fk_spot_tags_tag FOREIGN KEY (tag) REFERENCES tags(tag) ON DELETE CASCADE;

-- Locked spots take no new updates and no edits from non-admins.
ALTER TABLE spots ADD COLUMN locked TINYINT(1) NOT NULL DEFAULT 0;
