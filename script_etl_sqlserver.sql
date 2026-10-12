-- ============================================================================
-- PROYECTO FINAL: TRANSPORTES LUCHITO E.I.R.L.
-- SCRIPT ETL INTEGRADO (SQL SERVER - T-SQL)
-- 
-- PARTE 1: ETL Transaccional -> Data Mart Dimensional (DM_TransportesLuchito)
-- PARTE 2: Ingesta Masiva y Benchmark de Telemetría (Experimento EXP-01)
-- ============================================================================

USE [master];
GO

-- ============================================================================
-- PARTE 1: ETL DEPURACIÓN Y CARGA HACIA EL DATA MART DIMENSIONAL
-- ============================================================================

USE [DM_TransportesLuchito];
GO

-- 1.1 Poblar Dimensión Tiempo (Generador de calendario 2026)
SET NOCOUNT ON;
DECLARE @FechaInicio DATE = '2026-01-01';
DECLARE @FechaFin DATE = '2026-12-31';

WHILE @FechaInicio <= @FechaFin
BEGIN
    DECLARE @IdTiempo INT = YEAR(@FechaInicio) * 10000 + MONTH(@FechaInicio) * 100 + DAY(@FechaInicio);
    
    IF NOT EXISTS (SELECT 1 FROM dbo.Dim_Tiempo WHERE id_tiempo = @IdTiempo)
    BEGIN
        INSERT INTO dbo.Dim_Tiempo (id_tiempo, fecha, anio, mes, nombre_mes, dia, dia_semana, trimestre)
        VALUES (
            @IdTiempo,
            @FechaInicio,
            YEAR(@FechaInicio),
            MONTH(@FechaInicio),
            DATENAME(MONTH, @FechaInicio),
            DAY(@FechaInicio),
            DATENAME(WEEKDAY, @FechaInicio),
            DATEPART(QUARTER, @FechaInicio)
        );
    END
    SET @FechaInicio = DATEADD(DAY, 1, @FechaInicio);
END;
PRINT 'Dim_Tiempo sincronizada exitosamente.';
GO

-- 1.2 Carga de Dimensiones desde la Base Transaccional (TransportesLuchito)
-- Dim_Volquete
MERGE dbo.Dim_Volquete AS TARGET
USING TransportesLuchito.dbo.Volquete AS SOURCE
ON (TARGET.id_volquete = SOURCE.id_volquete)
WHEN MATCHED THEN
    UPDATE SET 
        TARGET.placa = SOURCE.placa,
        TARGET.capacidad_m3 = SOURCE.capacidad_m3,
        TARGET.marca = SOURCE.marca,
        TARGET.modelo = SOURCE.modelo,
        TARGET.estado = SOURCE.estado
WHEN NOT MATCHED THEN
    INSERT (id_volquete, placa, capacidad_m3, marca, modelo, estado)
    VALUES (SOURCE.id_volquete, SOURCE.placa, SOURCE.capacidad_m3, SOURCE.marca, SOURCE.modelo, SOURCE.estado);
PRINT 'Dim_Volquete sincronizada.';
GO

-- Dim_Conductor
MERGE dbo.Dim_Conductor AS TARGET
USING TransportesLuchito.dbo.Conductor AS SOURCE
ON (TARGET.id_conductor = SOURCE.id_conductor)
WHEN MATCHED THEN
    UPDATE SET 
        TARGET.dni = SOURCE.dni,
        TARGET.nombres = SOURCE.nombres,
        TARGET.apellidos = SOURCE.apellidos,
        TARGET.licencia_conducir = SOURCE.licencia_conducir,
        TARGET.categoria_licencia = SOURCE.categoria_licencia,
        TARGET.estado = SOURCE.estado
WHEN NOT MATCHED THEN
    INSERT (id_conductor, dni, nombres, apellidos, licencia_conducir, categoria_licencia, estado)
    VALUES (SOURCE.id_conductor, SOURCE.dni, SOURCE.nombres, SOURCE.apellidos, SOURCE.licencia_conducir, SOURCE.categoria_licencia, SOURCE.estado);
PRINT 'Dim_Conductor sincronizada.';
GO

-- Dim_ClienteFrente
MERGE dbo.Dim_ClienteFrente AS TARGET
USING TransportesLuchito.dbo.Cliente_Frente AS SOURCE
ON (TARGET.id_frente = SOURCE.id_frente)
WHEN MATCHED THEN
    UPDATE SET 
        TARGET.nombre_cliente = SOURCE.nombre_cliente,
        TARGET.nombre_frente = SOURCE.nombre_frente,
        TARGET.ubicacion = SOURCE.ubicacion,
        TARGET.contacto_responsable = SOURCE.contacto_responsable,
        TARGET.estado = SOURCE.estado
WHEN NOT MATCHED THEN
    INSERT (id_frente, nombre_cliente, nombre_frente, ubicacion, contacto_responsable, estado)
    VALUES (SOURCE.id_frente, SOURCE.nombre_cliente, SOURCE.nombre_frente, SOURCE.ubicacion, SOURCE.contacto_responsable, SOURCE.estado);
PRINT 'Dim_ClienteFrente sincronizada.';
GO

-- 1.3 Limpieza, Transformación y Carga a Fact_HorasMotor
-- Reglas de negocio:
-- - Validar que hora_fin > hora_inicio
-- - Recalcular duración en horas decimales con DATEDIFF
-- - Solo transferir al Data Mart los registros en estado 'validado'
TRUNCATE TABLE dbo.Fact_HorasMotor;

INSERT INTO dbo.Fact_HorasMotor (
    id_tiempo,
    id_volquete,
    id_conductor,
    id_frente,
    horas_trabajadas,
    flag_validado,
    estado_validacion,
    observaciones,
    fecha_carga
)
SELECT 
    YEAR(r.fecha) * 10000 + MONTH(r.fecha) * 100 + DAY(r.fecha) AS id_tiempo,
    r.id_volquete,
    r.id_conductor,
    r.id_frente,
    -- Recálculo de horas con precisión decimal
    CAST(DATEDIFF(MINUTE, r.hora_inicio, r.hora_fin) / 60.0 AS DECIMAL(5,2)) AS horas_trabajadas,
    1 AS flag_validado,
    r.estado_validacion,
    r.observaciones,
    GETDATE() AS fecha_carga
FROM TransportesLuchito.dbo.Registro_Horas_Motor r
WHERE r.hora_fin > r.hora_inicio
  AND r.estado_validacion = 'validado';

PRINT 'Fact_HorasMotor cargada exitosamente.';
GO

-- 1.4 Consulta de Verificación y Conciliación con Power BI
-- Debe sumar exactamente 43.0 horas (23.50 h MARSA, 9.50 h Poderosa, 10.00 h Barrick)
SELECT 
    cf.nombre_cliente,
    c.apellidos + ', ' + c.nombres AS Conductor,
    v.placa AS Volquete,
    SUM(f.horas_trabajadas) AS Total_Horas_Validadas
FROM dbo.Fact_HorasMotor f
INNER JOIN dbo.Dim_ClienteFrente cf ON f.id_frente = cf.id_frente
INNER JOIN dbo.Dim_Conductor c ON f.id_conductor = c.id_conductor
INNER JOIN dbo.Dim_Volquete v ON f.id_volquete = v.id_volquete
WHERE f.flag_validado = 1
GROUP BY cf.nombre_cliente, c.apellidos, c.nombres, v.placa
ORDER BY cf.nombre_cliente, Total_Horas_Validadas DESC;

SELECT SUM(horas_trabajadas) AS Total_General_DataMart FROM dbo.Fact_HorasMotor WHERE flag_validado = 1;
GO


-- ============================================================================
-- PARTE 2: INGESTA MASIVA Y BENCHMARKING DE TELEMETRÍA (EXP-01)
-- ============================================================================

USE [TransportesLuchito];
GO

-- 2.1 Creación de tabla Staging de telemetría (si no existe)
IF OBJECT_ID(N'dbo.Telemetria_Staging', N'U') IS NULL
BEGIN
    CREATE TABLE Telemetria_Staging (
        id_telemetria INT PRIMARY KEY,
        id_volquete INT,
        id_conductor INT,
        fecha_hora DATETIME,
        rpm_motor INT,
        estado VARCHAR(50)
    );
END;
GO

-- 2.2 Cargar registros desde CSV mediante BULK INSERT
-- (Ajustar la ruta del archivo telemetria_luchito.csv según el entorno local)
/*
BULK INSERT Telemetria_Staging
FROM 'F:\UTP-2026-II\big data\ef\proyecto corregido\BigData_Spark\telemetria_luchito.csv'
WITH (
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FIRSTROW = 2
);
GO
*/

-- 2.3 Medición de Rendimiento / Latencia T-SQL (EXP-01)
DBCC DROPCLEANBUFFERS;
DECLARE @StartTime DATETIME2 = SYSDATETIME();

SELECT 
    t.id_volquete,
    v.placa,
    t.id_conductor,
    c.nombres,
    c.apellidos,
    COUNT(*) AS minutos_totales_encendido
FROM Telemetria_Staging t
INNER JOIN Volquete v ON t.id_volquete = v.id_volquete
INNER JOIN Conductor c ON t.id_conductor = c.id_conductor
WHERE t.estado IN ('En movimiento', 'Detenido_Motor_Encendido')
GROUP BY t.id_volquete, v.placa, t.id_conductor, c.nombres, c.apellidos
ORDER BY minutos_totales_encendido DESC;

DECLARE @EndTime DATETIME2 = SYSDATETIME();
SELECT DATEDIFF(millisecond, @StartTime, @EndTime) AS Latencia_SQL_ms;
GO