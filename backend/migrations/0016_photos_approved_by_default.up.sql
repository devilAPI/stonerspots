-- Photos are moderated after the fact (reports, admin reject), like the
-- rest of the content. 0015 left every photo, old and new, pending, and
-- pending photos are never served, so nothing showed.
ALTER TABLE `photos`
  MODIFY COLUMN `status` ENUM('pending','approved','rejected') NOT NULL DEFAULT 'approved';
UPDATE `photos` SET `status` = 'approved' WHERE `status` = 'pending';
