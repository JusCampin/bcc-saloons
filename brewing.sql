-- Create table if it doesn't exist (base schema).
CREATE TABLE IF NOT EXISTS `brewing` (
  `id` uuid NOT NULL,
  `propname` varchar(255) DEFAULT NULL,
  `x` double DEFAULT NULL,
  `y` double DEFAULT NULL,
  `z` double DEFAULT NULL,
  `h` double DEFAULT NULL,
  `isbrewing` int(11) DEFAULT NULL,
  `stage` int(11) DEFAULT NULL,
  `currentbrew` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- Migration helpers: add new nullable columns only if they don't already exist.
-- This uses information_schema checks and prepared statements so the file can be
-- run against existing production databases safely.

-- Add `started_at_ms` (epoch ms when the current brew started)
SET @col_exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'brewing' AND COLUMN_NAME = 'started_at_ms');
SET @stmt = IF(@col_exists = 0,
  'ALTER TABLE `brewing` ADD COLUMN `started_at_ms` BIGINT NULL;',
  'SELECT "column started_at_ms already exists"');
PREPARE ps FROM @stmt; EXECUTE ps; DEALLOCATE PREPARE ps;

-- Add `stage_end_ms` (epoch ms when the current stage should end)
SET @col_exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'brewing' AND COLUMN_NAME = 'stage_end_ms');
SET @stmt = IF(@col_exists = 0,
  'ALTER TABLE `brewing` ADD COLUMN `stage_end_ms` BIGINT NULL;',
  'SELECT "column stage_end_ms already exists"');
PREPARE ps FROM @stmt; EXECUTE ps; DEALLOCATE PREPARE ps;

-- Add `placed_by` (who placed the prop; optional)
SET @col_exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'brewing' AND COLUMN_NAME = 'placed_by');
SET @stmt = IF(@col_exists = 0,
  'ALTER TABLE `brewing` ADD COLUMN `placed_by` VARCHAR(64) NULL;',
  'SELECT "column placed_by already exists"');
PREPARE ps FROM @stmt; EXECUTE ps; DEALLOCATE PREPARE ps;

-- Add `batch_amount` (optional amount per prop)
SET @col_exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'brewing' AND COLUMN_NAME = 'batch_amount');
SET @stmt = IF(@col_exists = 0,
  'ALTER TABLE `brewing` ADD COLUMN `batch_amount` INT NULL;',
  'SELECT "column batch_amount already exists"');
PREPARE ps FROM @stmt; EXECUTE ps; DEALLOCATE PREPARE ps;

-- Add `started_by` (who started the current brew; optional, char identifier)
SET @col_exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'brewing' AND COLUMN_NAME = 'started_by');
SET @stmt = IF(@col_exists = 0,
  'ALTER TABLE `brewing` ADD COLUMN `started_by` VARCHAR(64) NULL;',
  'SELECT "column started_by already exists"');
PREPARE ps FROM @stmt; EXECUTE ps; DEALLOCATE PREPARE ps;

INSERT INTO `items`(`item`, `label`, `limit`, `can_remove`, `type`, `usable`, `desc`)
VALUES
  ('corn_mash', 'Corn Mash', 10, 1, 'item_standard', 1, 'A batch of corn mash, ready for distillation.'),
  ('fruit_mash', 'Fruit Mash', 10, 1, 'item_standard', 1, 'A batch of fruit mash, ready for distillation.'),
  ('sweetened_mash', 'Sweetened Mash', 10, 1, 'item_standard', 1, 'A batch of sweetened mash, ready for distillation.')
ON DUPLICATE KEY UPDATE
  `label`=VALUES(`label`),
  `limit`=VALUES(`limit`),
  `can_remove`=VALUES(`can_remove`),
  `type`=VALUES(`type`),
  `usable`=VALUES(`usable`),
  `desc`=VALUES(`desc`);
