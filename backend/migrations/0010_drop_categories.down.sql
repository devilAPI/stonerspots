-- Re-adds the column only; the original category values are NOT restorable
-- (the tags created by the up migration are kept).
ALTER TABLE spots ADD COLUMN category ENUM('bench','river','lake','viewpoint','forest','park','other') NOT NULL DEFAULT 'other' AFTER description;
ALTER TABLE spots ADD KEY idx_spots_category (category);
