-- =============================================================================
-- Esquema y datos de prueba para tfg_app
-- =============================================================================
-- Tabla CLIENTES segun el modelo E/R del TFG.
-- Cargar con:
--   mysql -h <RDS_HOST> -u admin -p tfg_app < 01_clientes.sql
-- =============================================================================

CREATE TABLE IF NOT EXISTS clientes (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    nombre     VARCHAR(100)  NOT NULL,
    email      VARCHAR(150)  NOT NULL,
    telefono   VARCHAR(20)   DEFAULT NULL,
    empresa    VARCHAR(100)  DEFAULT NULL,
    created_at TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_clientes_email UNIQUE (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Indices auxiliares para busquedas frecuentes
CREATE INDEX idx_clientes_empresa ON clientes (empresa);
CREATE INDEX idx_clientes_created ON clientes (created_at);

-- Datos de prueba
INSERT IGNORE INTO clientes (nombre, email, telefono, empresa) VALUES
  ('Ana Garcia Lopez',     'ana.garcia@ejemplo.com',     '+34 612 345 678', 'TechSolutions S.L.'),
  ('Carlos Ruiz Martin',   'carlos.ruiz@ejemplo.com',    '+34 623 456 789', 'DataCloud Inc.'),
  ('Maria Fernandez Diaz', 'maria.fernandez@ejemplo.com','+34 634 567 890', 'CloudFirst S.A.'),
  ('Pedro Sanchez Gomez',  'pedro.sanchez@ejemplo.com',  '+34 645 678 901', NULL),
  ('Laura Martinez Perez', 'laura.martinez@ejemplo.com', NULL,              'InfraNet Corp.');

SELECT COUNT(*) AS total_clientes FROM clientes;
