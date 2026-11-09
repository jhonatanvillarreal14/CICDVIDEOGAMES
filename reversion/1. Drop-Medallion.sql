-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 1. Drop-Medallion | FI Videojuegos
-- MAGIC Importa este archivo como notebook SQL en reversion.
-- MAGIC Revisa la vista previa. Para retirar los registros, detén las ejecuciones que
-- MAGIC usan estas tablas, elige retirar_tablas y confirma con BAJA FI_VIDEOJUEGOS.
-- MAGIC Los archivos de las tablas externas se conservan en Azure.

-- COMMAND ----------

CREATE WIDGET DROPDOWN accion DEFAULT 'vista_previa'
  CHOICES SELECT * FROM VALUES ('vista_previa'), ('retirar_tablas');
CREATE WIDGET TEXT confirmacion DEFAULT '';

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW fi_videojuegos_revision_baja AS
WITH objetivos AS (
  SELECT * FROM VALUES
  ('golden', 'fi_gd_hechos_ventas'),
  ('golden', 'fi_gd_mejor_juego_familia_decada'),
  ('golden', 'fi_gd_ranking_familia_anio'),
  ('silver', 'fi_sl_metadatos'),
  ('silver', 'fi_sl_ventas_enriquecidas'),
  ('bronze', 'fi_br_nintendo'),
  ('bronze', 'fi_br_playstation'),
  ('bronze', 'fi_br_vgsales'),
  ('bronze', 'fi_br_xbox')
  AS permitidas(capa, nombre)
), revision AS (
  SELECT
    p.capa,
    p.nombre,
    concat('fi_videojuegos.', p.capa, '.', p.nombre) AS tabla,
    t.table_type AS tipo,
    t.data_source_format AS formato,
    t.storage_path AS ruta_actual,
    concat('abfss://', p.capa, '@adlsmardata1412jmvcc.dfs.core.windows.net/fi_videojuegos_jmcc/', p.nombre) AS ruta_esperada
  FROM objetivos p
  LEFT JOIN fi_videojuegos.information_schema.tables t
    ON t.table_schema = p.capa AND t.table_name = p.nombre
)
SELECT *,
  CASE
    WHEN tipo IS NULL THEN 'AUSENTE_O_NO_VISIBLE'
    WHEN tipo = 'EXTERNAL' AND upper(formato) = 'DELTA'
      AND rtrim('/', ruta_actual) = ruta_esperada THEN 'APTA'
    ELSE 'BLOQUEADA'
  END AS estado
FROM revision;

-- COMMAND ----------

SELECT tabla, tipo, formato, ruta_actual, ruta_esperada, estado
FROM fi_videojuegos_revision_baja
ORDER BY CASE capa WHEN 'golden' THEN 1 WHEN 'silver' THEN 2 ELSE 3 END, nombre;

-- COMMAND ----------

BEGIN
  DECLARE v_stmt STRING;
  DECLARE v_retiradas INT DEFAULT 0;

  SELECT assert_true(:accion IN ('vista_previa', 'retirar_tablas'), 'Accion invalida');
  IF :accion = 'retirar_tablas' THEN
    SELECT assert_true(trim(:confirmacion) = 'BAJA FI_VIDEOJUEGOS', 'Confirma con BAJA FI_VIDEOJUEGOS');
    SELECT assert_true(count(*) = 0, 'Hay tablas bloqueadas. Revisa el tipo y la ruta antes de continuar')
    FROM fi_videojuegos_revision_baja
    WHERE estado = 'BLOQUEADA';

    FOR r AS
      SELECT tabla
      FROM fi_videojuegos_revision_baja
      WHERE estado = 'APTA'
      ORDER BY CASE capa WHEN 'golden' THEN 1 WHEN 'silver' THEN 2 ELSE 3 END, nombre
    DO
      SET v_stmt = concat('DROP TABLE IF EXISTS ', r.tabla);
      EXECUTE IMMEDIATE v_stmt;
      SET v_retiradas = v_retiradas + 1;
    END FOR;

    SELECT v_retiradas AS registros_retirados;
  END IF;
END;
