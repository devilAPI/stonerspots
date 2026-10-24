-- Categories are gone; tags describe spots. Convert legacy categories into
-- tags first so nothing is lost, then drop the column.
INSERT IGNORE INTO spot_tags (spot_id, tag) SELECT id, 'seating' FROM spots WHERE category = 'bench';
INSERT IGNORE INTO spot_tags (spot_id, tag) SELECT id, 'water' FROM spots WHERE category IN ('river', 'lake');
INSERT IGNORE INTO spot_tags (spot_id, tag) SELECT id, 'view' FROM spots WHERE category = 'viewpoint';

ALTER TABLE spots DROP INDEX idx_spots_category;
ALTER TABLE spots DROP COLUMN category;
