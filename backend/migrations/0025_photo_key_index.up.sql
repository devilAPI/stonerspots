-- GET /media/* looks photos up by key or thumb_key (unauthenticated, on
-- every image in the feed); without an index each lookup scanned the table.
-- Keys are random per file, so they are unique.
ALTER TABLE photos
  ADD UNIQUE KEY uq_photos_key (`key`),
  ADD UNIQUE KEY uq_photos_thumb_key (thumb_key);
