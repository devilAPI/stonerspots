-- Cache of the no-consumption zone layer (internal/zones): the zones of one
-- grid tile as gzipped JSON, fetched from Overpass (OpenStreetMap, ODbL).
-- Kept across restarts so a restart does not refetch every tile.
CREATE TABLE zone_tiles (
  tile_key   VARCHAR(40) NOT NULL,
  data       MEDIUMBLOB NOT NULL,
  fetched_at DATETIME NOT NULL,
  PRIMARY KEY (tile_key),
  KEY idx_zone_tiles_fetched (fetched_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
