-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 5. DeltaSharing | FI Videojuegos
-- MAGIC Importa este archivo como notebook SQL en delta-sharing.
-- MAGIC Ejecuta primero con accion=vista_previa y luego con accion=preparar.
-- MAGIC Revisa la salida de SHOW ALL IN SHARE antes de conceder acceso.
-- MAGIC Para conceder acceso, usa un recipient existente y confirma COMPARTIR FI_VIDEOJUEGOS.

-- COMMAND ----------

CREATE WIDGET DROPDOWN accion DEFAULT 'vista_previa'
  CHOICES SELECT * FROM VALUES ('vista_previa'), ('preparar'), ('conceder_acceso');
CREATE WIDGET TEXT destinatario DEFAULT '';
CREATE WIDGET TEXT confirmacion DEFAULT '';

-- COMMAND ----------

BEGIN
  DECLARE v_stmt STRING;
  DECLARE v_tablas BIGINT;
  DECLARE v_ajenas BIGINT;

  SELECT assert_true(:accion IN ('vista_previa', 'preparar', 'conceder_acceso'), 'Accion invalida');

  IF :accion = 'vista_previa' THEN
    SELECT table_schema, table_name, table_type
    FROM fi_videojuegos.information_schema.tables
    WHERE (table_schema = 'silver' AND table_name = 'fi_sl_ventas_enriquecidas')
       OR (table_schema = 'golden' AND table_name = 'fi_gd_ranking_familia_anio');
  ELSE
    SET v_ajenas = (
      SELECT count(*)
      FROM system.information_schema.table_share_usage
      WHERE share_name = 'fi_videojuegos_share'
        AND NOT (catalog_name = 'fi_videojuegos' AND (
          (schema_name = 'silver' AND table_name = 'fi_sl_ventas_enriquecidas')
          OR (schema_name = 'golden' AND table_name = 'fi_gd_ranking_familia_anio')
        ))
    );
    SELECT assert_true(v_ajenas = 0, 'El share contiene otras tablas. Revisa su contenido');

    IF :accion = 'preparar' THEN
      SELECT assert_true(count(*) = 2, 'Las dos tablas del proyecto deben existir')
      FROM fi_videojuegos.information_schema.tables
      WHERE (table_schema = 'silver' AND table_name = 'fi_sl_ventas_enriquecidas')
         OR (table_schema = 'golden' AND table_name = 'fi_gd_ranking_familia_anio');

      CREATE SHARE IF NOT EXISTS fi_videojuegos_share COMMENT 'FI Videojuegos - Silver y Golden';

      IF NOT EXISTS (
        SELECT 1 FROM system.information_schema.table_share_usage
        WHERE share_name = 'fi_videojuegos_share' AND catalog_name = 'fi_videojuegos'
          AND schema_name = 'silver' AND table_name = 'fi_sl_ventas_enriquecidas'
      ) THEN
        ALTER SHARE fi_videojuegos_share
          ADD TABLE fi_videojuegos.silver.fi_sl_ventas_enriquecidas WITHOUT HISTORY;
      END IF;

      IF NOT EXISTS (
        SELECT 1 FROM system.information_schema.table_share_usage
        WHERE share_name = 'fi_videojuegos_share' AND catalog_name = 'fi_videojuegos'
          AND schema_name = 'golden' AND table_name = 'fi_gd_ranking_familia_anio'
      ) THEN
        ALTER SHARE fi_videojuegos_share
          ADD TABLE fi_videojuegos.golden.fi_gd_ranking_familia_anio WITHOUT HISTORY;
      END IF;
    ELSE
      SET v_tablas = (
        SELECT count(DISTINCT concat(schema_name, '.', table_name))
        FROM system.information_schema.table_share_usage
        WHERE share_name = 'fi_videojuegos_share' AND catalog_name = 'fi_videojuegos'
      );
      SELECT assert_true(v_tablas = 2, 'Ejecuta preparar y revisa el contenido del share');
      SELECT assert_true(trim(:destinatario) RLIKE '^[A-Za-z0-9_-]+$', 'Indica un recipient existente');
      SELECT assert_true(trim(:confirmacion) = 'COMPARTIR FI_VIDEOJUEGOS', 'Confirma despues de revisar SHOW ALL IN SHARE');
      SET v_stmt = concat(
        'GRANT SELECT ON SHARE fi_videojuegos_share TO RECIPIENT `',
        trim(:destinatario), '`'
      );
      EXECUTE IMMEDIATE v_stmt;
    END IF;

    SHOW ALL IN SHARE fi_videojuegos_share;
  END IF;
END;
