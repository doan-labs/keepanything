-- Trashing cancels an item's jobs but used to leave its processing_status alone, so items trashed
-- mid-pipeline kept a running status and their cards pulsed forever. Settle the ones already in the
-- trash the same way item-service does now.
UPDATE items
SET processing_status = 'PARTIAL'
WHERE deleted_at IS NOT NULL
  AND processing_status NOT IN ('READY', 'PARTIAL', 'EXTRACTION_FAILED', 'AI_FAILED');
