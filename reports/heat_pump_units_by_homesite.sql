-- Heat pump units by homesite (proof of concept)
--
-- One row per heat pump unit on each homesite's "Heat Pumps" task.
--
-- The Smartsheet project schedules store units in separate columns:
--   "Heat Pump Model #1" .. "Heat Pump Model #8"
--   "Heat Pump Serial #1" .. "Heat Pump Serial #8"
-- fct__enterprise_master_project_data keeps only some of these columns, so the
-- values are read from the cell-level table, which has every column.
-- Model #n is paired with Serial #n (unit_number = n).
-- Cells that hold two units split by " / " are kept as one value.

WITH heat_pump_tasks AS (
  SELECT
    sheet_id,
    row_id,
    job_unit_unique_id,
    region,
    community_name,
    sheet_name,
    homesite,
    lot,
    model_type,
    swing,
    task_status,
    actual_finish
  FROM `dandelion-tf-production.dbt_dandelion_operations.fct__enterprise_master_project_data`
  WHERE task_name = 'Heat Pumps'
),

-- One row per filled-in heat pump model or serial cell.
-- Matched on the column title, since field_key is not consistent across sheets.
heat_pump_cells AS (
  SELECT
    sheet_id,
    row_id,
    column_title,
    REGEXP_EXTRACT(column_title, r'^Heat Pump (Model|Serial) #') AS cell_kind,
    CAST(REGEXP_EXTRACT(column_title, r'#(\d+)$') AS INT64) AS unit_number,
    NULLIF(TRIM(value), '') AS cell_value
  FROM `dandelion-tf-production.dbt_dandelion_prep.stg_smartsheet__cell`
  WHERE REGEXP_CONTAINS(column_title, r'^Heat Pump (Model|Serial) #\d+$')
    AND NULLIF(TRIM(value), '') IS NOT NULL
),

-- One row per unit: Model #n and Serial #n side by side.
units AS (
  SELECT
    sheet_id,
    row_id,
    unit_number,
    MAX(IF(cell_kind = 'Model', cell_value, NULL)) AS heat_pump_model,
    MAX(IF(cell_kind = 'Serial', cell_value, NULL)) AS heat_pump_serial
  FROM heat_pump_cells
  GROUP BY sheet_id, row_id, unit_number
),

unit_counts AS (
  SELECT
    sheet_id,
    row_id,
    COUNT(heat_pump_model) AS model_count,
    COUNT(heat_pump_serial) AS serial_count
  FROM units
  GROUP BY sheet_id, row_id
)

SELECT
  tasks.sheet_id,
  tasks.row_id,
  tasks.job_unit_unique_id AS job_unit_number,
  tasks.region,
  tasks.community_name,
  tasks.sheet_name,
  tasks.homesite,
  tasks.lot,
  tasks.model_type,
  tasks.swing,
  tasks.task_status,
  tasks.actual_finish,
  units.unit_number,
  units.heat_pump_model,
  units.heat_pump_serial,
  unit_counts.model_count,
  unit_counts.serial_count,
  units.heat_pump_model IS NULL AS serial_without_model
FROM units
JOIN heat_pump_tasks AS tasks
  ON units.sheet_id = tasks.sheet_id
  AND units.row_id = tasks.row_id
JOIN unit_counts
  ON units.sheet_id = unit_counts.sheet_id
  AND units.row_id = unit_counts.row_id
ORDER BY tasks.community_name, tasks.homesite, units.unit_number
