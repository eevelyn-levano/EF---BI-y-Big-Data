-- ============================================================================
-- PROYECTO FINAL: TRANSPORTES LUCHITO E.I.R.L.
-- SCRIPT DDL: CREACIÓN DEL DATA MART DIMENSIONAL (DM_TransportesLuchito)
-- Esquema en Estrella (Star Schema) según metodología de Ralph Kimball
-- ============================================================================

USE [master]
GO

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'DM_TransportesLuchito')
BEGIN
    CREATE DATABASE [DM_TransportesLuchito];
END
GO

USE [DM_TransportesLuchito]
GO

-- 1. Dimensión Tiempo
IF OBJECT_ID(N'[dbo].[Fact_HorasMotor]', N'U') IS NOT NULL DROP TABLE [dbo].[Fact_HorasMotor];
IF OBJECT_ID(N'[dbo].[Dim_Tiempo]', N'U') IS NOT NULL DROP TABLE [dbo].[Dim_Tiempo];
CREATE TABLE [dbo].[Dim_Tiempo] (
    [id_tiempo] INT PRIMARY KEY, -- Formato numérico YYYYMMDD
    [fecha] DATE NOT NULL UNIQUE,
    [anio] INT NOT NULL,
    [mes] INT NOT NULL,
    [nombre_mes] VARCHAR(20) NOT NULL,
    [dia] INT NOT NULL,
    [dia_semana] VARCHAR(20) NOT NULL,
    [trimestre] INT NOT NULL
);
GO

-- 2. Dimensión Volquete
IF OBJECT_ID(N'[dbo].[Dim_Volquete]', N'U') IS NOT NULL DROP TABLE [dbo].[Dim_Volquete];
CREATE TABLE [dbo].[Dim_Volquete] (
    [id_volquete] INT PRIMARY KEY,
    [placa] VARCHAR(10) NOT NULL UNIQUE,
    [capacidad_m3] DECIMAL(5,2) NULL,
    [marca] VARCHAR(50) NULL,
    [modelo] VARCHAR(50) NULL,
    [estado] VARCHAR(20) NULL
);
GO

-- 3. Dimensión Conductor
IF OBJECT_ID(N'[dbo].[Dim_Conductor]', N'U') IS NOT NULL DROP TABLE [dbo].[Dim_Conductor];
CREATE TABLE [dbo].[Dim_Conductor] (
    [id_conductor] INT PRIMARY KEY,
    [dni] VARCHAR(8) NOT NULL,
    [nombres] VARCHAR(50) NOT NULL,
    [apellidos] VARCHAR(50) NOT NULL,
    [licencia_conducir] VARCHAR(20) NULL,
    [categoria_licencia] VARCHAR(10) NULL,
    [estado] VARCHAR(20) NULL
);
GO

-- 4. Dimensión Cliente / Frente
IF OBJECT_ID(N'[dbo].[Dim_ClienteFrente]', N'U') IS NOT NULL DROP TABLE [dbo].[Dim_ClienteFrente];
CREATE TABLE [dbo].[Dim_ClienteFrente] (
    [id_frente] INT PRIMARY KEY,
    [nombre_cliente] VARCHAR(100) NOT NULL,
    [nombre_frente] VARCHAR(100) NOT NULL,
    [ubicacion] VARCHAR(150) NULL,
    [contacto_responsable] VARCHAR(100) NULL,
    [estado] VARCHAR(20) NULL
);
GO

-- 5. Tabla de Hechos: Fact_HorasMotor
CREATE TABLE [dbo].[Fact_HorasMotor] (
    [id_fact] INT IDENTITY(1,1) PRIMARY KEY,
    [id_tiempo] INT NOT NULL,
    [id_volquete] INT NOT NULL,
    [id_conductor] INT NOT NULL,
    [id_frente] INT NOT NULL,
    [horas_trabajadas] DECIMAL(5,2) NOT NULL,
    [flag_validado] BIT NOT NULL DEFAULT 1,
    [estado_validacion] VARCHAR(20) NOT NULL,
    [observaciones] VARCHAR(255) NULL,
    [fecha_carga] DATETIME DEFAULT GETDATE(),
    CONSTRAINT [FK_Fact_Tiempo] FOREIGN KEY ([id_tiempo]) REFERENCES [dbo].[Dim_Tiempo]([id_tiempo]),
    CONSTRAINT [FK_Fact_Volquete] FOREIGN KEY ([id_volquete]) REFERENCES [dbo].[Dim_Volquete]([id_volquete]),
    CONSTRAINT [FK_Fact_Conductor] FOREIGN KEY ([id_conductor]) REFERENCES [dbo].[Dim_Conductor]([id_conductor]),
    CONSTRAINT [FK_Fact_Frente] FOREIGN KEY ([id_frente]) REFERENCES [dbo].[Dim_ClienteFrente]([id_frente])
);
GO

-- Índices para acelerar el filtrado analítico (OLAP)
CREATE NONCLUSTERED INDEX [IX_Fact_Tiempo] ON [dbo].[Fact_HorasMotor]([id_tiempo]);
CREATE NONCLUSTERED INDEX [IX_Fact_Volquete] ON [dbo].[Fact_HorasMotor]([id_volquete]);
CREATE NONCLUSTERED INDEX [IX_Fact_Conductor] ON [dbo].[Fact_HorasMotor]([id_conductor]);
CREATE NONCLUSTERED INDEX [IX_Fact_Frente] ON [dbo].[Fact_HorasMotor]([id_frente]);
GO
