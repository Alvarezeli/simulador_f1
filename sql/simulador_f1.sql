-- =====================================================================
-- HITO 3: SCRIPT SQL COMPLETO - SIMULADOR DE FÓRMULA 1
-- Requiere MySQL 8.0.16+ o MariaDB 10.2+ (CHECK y RANK() OVER)
-- =====================================================================

SET NAMES utf8mb4;   -- para que las tildes y la ñ se guarden bien

DROP DATABASE IF EXISTS simulador_f1;
CREATE DATABASE simulador_f1 CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE simulador_f1;

-- =====================================================================
-- 1. DDL: CREACIÓN DE TABLAS (PK, FK, UNIQUE, NOT NULL y CHECK)
-- =====================================================================

CREATE TABLE usuario (
    id_usuario INT AUTO_INCREMENT PRIMARY KEY,
    nombre_usuario VARCHAR(50) NOT NULL UNIQUE,
    contrasena VARCHAR(255) NOT NULL          -- hash SHA2 de la contraseña
);

CREATE TABLE temporada (
    id_temporada INT AUTO_INCREMENT PRIMARY KEY,
    anio SMALLINT NOT NULL UNIQUE,
    presupuesto_inicial DECIMAL(12,2) NOT NULL CHECK (presupuesto_inicial > 0)
);

CREATE TABLE escuderia (
    id_escuderia INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE,
    pais VARCHAR(50)
);

CREATE TABLE partida (
    id_partida INT AUTO_INCREMENT PRIMARY KEY,
    presupuesto DECIMAL(12,2) NOT NULL CHECK (presupuesto >= 0),
    estado TINYINT NOT NULL CHECK (estado IN (0, 1)),   -- 0 = en curso, 1 = finalizada
    id_escuderia INT NOT NULL,
    id_usuario INT NOT NULL UNIQUE,                     -- cada usuario tiene una sola partida
    id_temporada INT NOT NULL,
    CONSTRAINT fk_partida_escuderia FOREIGN KEY (id_escuderia) REFERENCES escuderia(id_escuderia)
       ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_partida_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario)
       ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_partida_temporada FOREIGN KEY (id_temporada) REFERENCES temporada(id_temporada)
       ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE piloto (
    id_piloto INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL,
    sueldo_pedido DECIMAL(12,2) NOT NULL CHECK (sueldo_pedido > 0),
    habilidad INT NOT NULL CHECK (habilidad BETWEEN 1 AND 100),
    id_escuderia INT NULL,                              -- NULL = piloto libre de mercado
    CONSTRAINT fk_piloto_escuderia FOREIGN KEY (id_escuderia) REFERENCES escuderia(id_escuderia)
       ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE contrato (
    id_contrato INT AUTO_INCREMENT PRIMARY KEY,
    id_partida INT NOT NULL,
    id_piloto INT NOT NULL,
    sueldo_pactado DECIMAL(12,2) NOT NULL CHECK (sueldo_pactado >= 0),
    CONSTRAINT fk_contrato_partida FOREIGN KEY (id_partida) REFERENCES partida(id_partida)
       ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_contrato_piloto FOREIGN KEY (id_piloto) REFERENCES piloto(id_piloto)
       ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT uq_partida_piloto UNIQUE (id_partida, id_piloto)   -- un piloto una vez por partida
);

CREATE TABLE componentes (
    id_componentes INT AUTO_INCREMENT PRIMARY KEY,
    tipo VARCHAR(50),
    costo DECIMAL(12,2) NOT NULL CHECK (costo > 0),
    rendimiento_extra DECIMAL(6,3) NOT NULL CHECK (rendimiento_extra >= 0),   -- segundos que resta
    descripcion VARCHAR(250),
    durabilidad INT NOT NULL CHECK (durabilidad > 0)                           -- carreras que dura
);

CREATE TABLE circuito (
    id_circuito INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    longitud_km DECIMAL(5,3) NOT NULL,
    pais VARCHAR(50),
    tiempo_base DECIMAL(8,3) NOT NULL CHECK (tiempo_base > 0)   -- segundos
);

CREATE TABLE carrera (
    id_carrera INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    orden TINYINT NOT NULL CHECK (orden > 0),
    fecha DATE NOT NULL,
    id_circuito INT NOT NULL,
    id_temporada INT NOT NULL,
    CONSTRAINT fk_carrera_circuito FOREIGN KEY (id_circuito) REFERENCES circuito(id_circuito)
       ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_carrera_temporada FOREIGN KEY (id_temporada) REFERENCES temporada(id_temporada)
       ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT uq_temporada_orden UNIQUE (id_temporada, orden),
    CONSTRAINT uq_temporada_fecha UNIQUE (id_temporada, fecha)   -- un piloto no corre dos carreras el mismo día
);

CREATE TABLE compra (
    id_compra INT AUTO_INCREMENT PRIMARY KEY,
    id_partida INT NOT NULL,
    id_componentes INT NOT NULL,
    id_carrera INT NOT NULL,                            -- carrera ANTES de la cual se compró
    precio_pagado DECIMAL(12,2) NOT NULL CHECK (precio_pagado >= 0),
    CONSTRAINT fk_compra_partida FOREIGN KEY (id_partida) REFERENCES partida(id_partida)
       ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_compra_componentes FOREIGN KEY (id_componentes) REFERENCES componentes(id_componentes)
       ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_compra_carrera FOREIGN KEY (id_carrera) REFERENCES carrera(id_carrera)
       ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT uq_compra_partida_comp_carrera UNIQUE (id_partida, id_componentes, id_carrera)
);

CREATE TABLE resultado (
    id_resultado INT AUTO_INCREMENT PRIMARY KEY,
    tiempo DECIMAL(8,3) NOT NULL CHECK (tiempo > 0),    -- segundos con milésimas
    id_partida INT NULL,                                -- NULL = tiempos de rivales de la semilla
    id_carrera INT NOT NULL,
    id_piloto INT NOT NULL,
    CONSTRAINT fk_resultado_partida FOREIGN KEY (id_partida) REFERENCES partida(id_partida)
       ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_resultado_carrera FOREIGN KEY (id_carrera) REFERENCES carrera(id_carrera)
       ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_resultado_piloto FOREIGN KEY (id_piloto) REFERENCES piloto(id_piloto)
       ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT uq_resultado_partida_carrera_piloto UNIQUE (id_partida, id_carrera, id_piloto)
);

CREATE TABLE puntos_por_posicion (
    posicion INT PRIMARY KEY CHECK (posicion > 0),
    puntos INT NOT NULL CHECK (puntos >= 0)
);


-- =====================================================================
-- 2. DML: DATOS SEMILLA
-- =====================================================================

INSERT INTO temporada (anio, presupuesto_inicial) VALUES (2026, 50000000.00);

INSERT INTO escuderia (nombre, pais) VALUES
('Ferrari',         'Italia'),        -- 1
('Red Bull Racing', 'Austria'),       -- 2
('Mercedes',        'Alemania'),      -- 3
('McLaren',         'Reino Unido'),   -- 4
('Williams',        'Reino Unido'),   -- 5
('Alpine',          'Francia');       -- 6

INSERT INTO circuito (nombre, longitud_km, pais, tiempo_base) VALUES
('Monza',             5.793, 'Italia',      80.000),
('Silverstone',       5.891, 'Reino Unido', 90.000),
('Spa-Francorchamps', 7.004, 'Bélgica',    105.000),
('Monaco',            3.337, 'Mónaco',      72.000);

INSERT INTO carrera (nombre, orden, fecha, id_circuito, id_temporada) VALUES
('GP de Italia',       1, '2026-03-10', 1, 1),
('GP de Gran Bretaña', 2, '2026-04-12', 2, 1),
('GP de Bélgica',      3, '2026-05-15', 3, 1),
('GP de Mónaco',       4, '2026-06-20', 4, 1);

INSERT INTO componentes (tipo, costo, rendimiento_extra, descripcion, durabilidad) VALUES
('Motor',        5000000.00, 1.500, 'Motor evolucionado etapa 1',   2),   -- 1
('Aerodinámica', 3000000.00, 0.800, 'Ala delantera de alta carga',  3),   -- 2
('Neumáticos',   1500000.00, 0.500, 'Compuesto blando especial',    1),   -- 3
('Frenos',       2000000.00, 0.700, 'Discos de carbono reforzados', 2);   -- 4

-- IMPORTANTE: los ids de piloto dependen de este orden (los resultados los usan)
INSERT INTO piloto (nombre, sueldo_pedido, habilidad, id_escuderia) VALUES
-- Rivales (2 por escudería)
('Max Verstappen',    15000000.00, 98, 2),      -- 1
('Isack Hadjar',       6000000.00, 78, 2),      -- 2
('Lewis Hamilton',    14000000.00, 95, 1),      -- 3
('Charles Leclerc',   12000000.00, 92, 1),      -- 4
('Lando Norris',      11000000.00, 91, 4),      -- 5
('Oscar Piastri',     10000000.00, 88, 4),      -- 6
('George Russell',    11000000.00, 90, 3),      -- 7
('Kimi Antonelli',     7000000.00, 84, 3),      -- 8
('Carlos Sainz',       9000000.00, 86, 5),      -- 9
('Alex Albon',         8000000.00, 83, 5),      -- 10
('Pierre Gasly',       8000000.00, 82, 6),      -- 11
('Esteban Ocon',       6000000.00, 79, 6),      -- 12
-- Libres de mercado (más habilidad, más caro)
('Franco Colapinto',  18000000.00, 85, NULL),   -- 13
('Gabriel Bortoleto', 15000000.00, 83, NULL),   -- 14
('Liam Lawson',       13000000.00, 82, NULL),   -- 15
('Checo Perez',       11000000.00, 80, NULL),   -- 16
('Rafael Camara',      9000000.00, 78, NULL),   -- 17
('Oliver Bearman',     7000000.00, 75, NULL),   -- 18
('Yuki Tsunoda',       6000000.00, 74, NULL);   -- 19

-- Las contraseñas se guardan hasheadas con SHA2 (nunca en texto plano).
-- Contraseñas de prueba: sebastian123, lucia123 y martin123
INSERT INTO usuario (nombre_usuario, contrasena) VALUES
('sebastian', SHA2('sebastian123', 256)),
('lucia',     SHA2('lucia123', 256)),
('martin',    SHA2('martin123', 256));

-- Presupuesto = 50.000.000 - sueldos de los pilotos - compras
INSERT INTO partida (presupuesto, estado, id_escuderia, id_usuario, id_temporada) VALUES
(13000000.00, 1, 3, 1, 1),   -- Sebastián, Mercedes: 50M - 24M pilotos - 13M compras. Finalizada
(23000000.00, 0, 1, 2, 1),   -- Lucía, Ferrari:      50M - 22M pilotos - 5M compras. En curso
(37000000.00, 0, 4, 3, 1);   -- Martín, McLaren:     50M - 13M pilotos. En curso

-- El sueldo pactado es el sueldo pedido al momento de contratar
INSERT INTO contrato (id_partida, id_piloto, sueldo_pactado) VALUES
(1, 13, 18000000.00),   -- Sebastián: Colapinto
(1, 19,  6000000.00),   -- Sebastián: Tsunoda
(2, 15, 13000000.00),   -- Lucía: Lawson
(2, 17,  9000000.00),   -- Lucía: Camara
(3, 18,  7000000.00),   -- Martín: Bearman
(3, 19,  6000000.00);   -- Martín: Tsunoda (el mismo piloto puede estar en varias partidas)

INSERT INTO puntos_por_posicion (posicion, puntos) VALUES
(1, 25), (2, 18), (3, 15), (4, 12), (5, 10), (6, 8), (7, 6), (8, 4), (9, 2), (10, 1);

-- Tiempos de los pilotos rivales (id_partida NULL = vienen de la semilla)
-- Generados con: tiempo_base - habilidad x 0,05 - 1 (auto rival) + variación
-- Formato: (tiempo, id_partida, id_carrera, id_piloto)
INSERT INTO resultado (tiempo, id_partida, id_carrera, id_piloto) VALUES
-- Carrera 1: GP de Italia (Monza)
(74.100, NULL, 1, 1),   -- Verstappen
(76.150, NULL, 1, 2),   -- Hadjar
(74.850, NULL, 1, 3),   -- Hamilton
(74.550, NULL, 1, 4),   -- Leclerc
(75.650, NULL, 1, 5),   -- Norris
(75.350, NULL, 1, 6),   -- Piastri
(74.800, NULL, 1, 7),   -- Russell
(76.150, NULL, 1, 8),   -- Antonelli
(75.600, NULL, 1, 9),   -- Sainz
(75.300, NULL, 1, 10),  -- Albon
(74.900, NULL, 1, 11),  -- Gasly
(76.100, NULL, 1, 12),  -- Ocon
-- Carrera 2: GP de Gran Bretaña (Silverstone)
(84.550, NULL, 2, 1),   -- Verstappen
(85.100, NULL, 2, 2),   -- Hadjar
(85.300, NULL, 2, 3),   -- Hamilton
(85.000, NULL, 2, 4),   -- Leclerc
(84.600, NULL, 2, 5),   -- Norris
(85.800, NULL, 2, 6),   -- Piastri
(85.250, NULL, 2, 7),   -- Russell
(85.100, NULL, 2, 8),   -- Antonelli
(86.050, NULL, 2, 9),   -- Sainz
(85.750, NULL, 2, 10),  -- Albon
(85.350, NULL, 2, 11),  -- Gasly
(85.050, NULL, 2, 12),  -- Ocon
-- Carrera 3: GP de Bélgica (Spa)
(100.000, NULL, 3, 1),  -- Verstappen
(100.550, NULL, 3, 2),  -- Hadjar
(99.250, NULL, 3, 3),   -- Hamilton
(100.450, NULL, 3, 4),  -- Leclerc
(100.050, NULL, 3, 5),  -- Norris
(99.750, NULL, 3, 6),   -- Piastri
(100.700, NULL, 3, 7),  -- Russell
(100.550, NULL, 3, 8),  -- Antonelli
(100.000, NULL, 3, 9),  -- Sainz
(101.200, NULL, 3, 10), -- Albon
(100.800, NULL, 3, 11), -- Gasly
(100.500, NULL, 3, 12), -- Ocon
-- Carrera 4: GP de Mónaco
(67.450, NULL, 4, 1),   -- Verstappen
(68.000, NULL, 4, 2),   -- Hadjar
(66.700, NULL, 4, 3),   -- Hamilton
(66.400, NULL, 4, 4),   -- Leclerc
(67.500, NULL, 4, 5),   -- Norris
(67.200, NULL, 4, 6),   -- Piastri
(66.650, NULL, 4, 7),   -- Russell
(68.000, NULL, 4, 8),   -- Antonelli
(67.450, NULL, 4, 9),   -- Sainz
(67.150, NULL, 4, 10),  -- Albon
(68.250, NULL, 4, 11),  -- Gasly
(67.950, NULL, 4, 12);  -- Ocon

-- Tiempos de los pilotos de las partidas de prueba
-- tiempo = tiempo_base - habilidad x 0,05 - componentes activos + variación
INSERT INTO resultado (tiempo, id_partida, id_carrera, id_piloto) VALUES
-- Sebastián (partida 1): corrió las 4 carreras
(74.050, 1, 1, 13),   -- Colapinto
(74.900, 1, 1, 19),   -- Tsunoda
(84.500, 1, 2, 13),   -- Colapinto
(85.350, 1, 2, 19),   -- Tsunoda
(98.450, 1, 3, 13),   -- Colapinto
(99.300, 1, 3, 19),   -- Tsunoda
(66.700, 1, 4, 13),   -- Colapinto
(67.550, 1, 4, 19),   -- Tsunoda
-- Lucía (partida 2): corrió 2 carreras
(75.600, 2, 1, 15),   -- Lawson
(74.900, 2, 1, 17),   -- Camara
(84.550, 2, 2, 15),   -- Lawson
(85.350, 2, 2, 17);   -- Camara
-- Martín (partida 3): todavía no corrió

-- id_carrera = carrera ANTES de la cual se compró el componente
INSERT INTO compra (id_partida, id_componentes, id_carrera, precio_pagado) VALUES
(1, 1, 1, 5000000.00),   -- Sebastián: Motor antes de la carrera 1 (dura 2: carreras 1 y 2)
(1, 2, 1, 3000000.00),   -- Sebastián: Aerodinámica antes de la carrera 1 (dura 3: carreras 1, 2 y 3)
(1, 1, 3, 5000000.00),   -- Sebastián: vuelve a comprar el Motor antes de la carrera 3 (ya se había gastado)
(2, 2, 1, 3000000.00),   -- Lucía: Aerodinámica antes de la carrera 1
(2, 4, 1, 2000000.00);   -- Lucía: Frenos antes de la carrera 1 (dura 2)


-- =====================================================================
-- 3. VISTAS
-- =====================================================================

-- Posición de cada piloto en cada carrera de cada partida.
-- Junta los tiempos del jugador con los de los rivales y los ordena por tiempo.
CREATE VIEW v_posiciones AS
SELECT t.id_partida, t.id_carrera, t.id_piloto, t.tiempo, t.es_jugador,
       RANK() OVER (PARTITION BY t.id_partida, t.id_carrera ORDER BY t.tiempo) AS posicion
FROM (
    -- Parte A: los tiempos de los pilotos del jugador
    SELECT r.id_partida, r.id_carrera, r.id_piloto, r.tiempo, 1 AS es_jugador
    FROM resultado r
    WHERE r.id_partida IS NOT NULL

    UNION ALL

    -- Parte B: los tiempos de los rivales, copiados para cada partida
    SELECT pa.id_partida, r.id_carrera, r.id_piloto, r.tiempo, 0 AS es_jugador
    FROM partida pa
    JOIN resultado r ON r.id_partida IS NULL
    JOIN piloto pi ON pi.id_piloto = r.id_piloto
    WHERE pi.id_escuderia <> pa.id_escuderia          -- excluye la escudería elegida
      AND r.id_carrera IN (SELECT r2.id_carrera       -- solo carreras que la partida ya corrió
                           FROM resultado r2
                           WHERE r2.id_partida = pa.id_partida)
) t;

-- Lo mismo, con los puntos de cada posición (fuera del top 10 = 0 puntos)
CREATE VIEW v_puntos AS
SELECT v.id_partida, v.id_carrera, v.id_piloto, v.tiempo, v.es_jugador, v.posicion,
       COALESCE(pp.puntos, 0) AS puntos
FROM v_posiciones v
LEFT JOIN puntos_por_posicion pp ON pp.posicion = v.posicion;

-- Ranking de usuarios: suma de los puntos de los pilotos del jugador
CREATE VIEW v_ranking_usuarios AS
SELECT u.nombre_usuario, e.nombre AS escuderia,
       COALESCE(SUM(vp.puntos), 0) AS puntos_totales
FROM partida pa
JOIN usuario u ON u.id_usuario = pa.id_usuario
JOIN escuderia e ON e.id_escuderia = pa.id_escuderia
LEFT JOIN v_puntos vp ON vp.id_partida = pa.id_partida AND vp.es_jugador = 1
GROUP BY pa.id_partida, u.nombre_usuario, e.nombre;


-- =====================================================================
-- 4. CONSULTAS (10 consultas del proyecto)
-- =====================================================================

-- Consulta 1 (JOIN de 4 tablas): ¿Qué pilotos contrató cada usuario y cuánto pagó?
SELECT u.nombre_usuario, p.nombre AS piloto, co.sueldo_pactado
FROM contrato co
JOIN partida pa ON pa.id_partida = co.id_partida
JOIN usuario u  ON u.id_usuario  = pa.id_usuario
JOIN piloto p   ON p.id_piloto   = co.id_piloto;

-- Consulta 2 (ANTI-JOIN + subconsulta): ¿Qué pilotos libres puede contratar todavía Martín?
SELECT p.nombre, p.habilidad, p.sueldo_pedido
FROM piloto p
LEFT JOIN contrato c
       ON c.id_piloto = p.id_piloto
      AND c.id_partida = (SELECT pa.id_partida
                          FROM partida pa
                          JOIN usuario u ON u.id_usuario = pa.id_usuario
                          WHERE u.nombre_usuario = 'martin')
WHERE p.id_escuderia IS NULL
  AND c.id_contrato IS NULL;

-- Consulta 3 (SUBCONSULTA ESCALAR): ¿Qué componentes cuestan más que el promedio?
SELECT tipo, costo
FROM componentes
WHERE costo > (SELECT AVG(costo) FROM componentes);

-- Consulta 4 (GROUP BY + HAVING): ¿Qué usuarios gastaron más de 5.000.000 en componentes?
SELECT u.nombre_usuario, SUM(c.precio_pagado) AS total_gastado
FROM compra c
JOIN partida pa ON pa.id_partida = c.id_partida
JOIN usuario u  ON u.id_usuario  = pa.id_usuario
GROUP BY u.nombre_usuario
HAVING SUM(c.precio_pagado) > 5000000;

-- Consulta 5 (JOIN de 3 tablas): ¿Cuál es el calendario de la temporada?
SELECT t.anio, ca.orden, ca.nombre AS gran_premio, ci.nombre AS circuito, ca.fecha
FROM carrera ca
JOIN circuito ci ON ci.id_circuito = ca.id_circuito
JOIN temporada t ON t.id_temporada = ca.id_temporada
ORDER BY ca.orden;

-- Consulta 6 (JOIN de 5 tablas): ¿Qué componentes compró cada usuario y antes de qué carrera?
SELECT u.nombre_usuario, co.tipo, ca.nombre AS antes_de, c.precio_pagado
FROM compra c
JOIN partida pa     ON pa.id_partida     = c.id_partida
JOIN usuario u      ON u.id_usuario      = pa.id_usuario
JOIN componentes co ON co.id_componentes = c.id_componentes
JOIN carrera ca     ON ca.id_carrera     = c.id_carrera
ORDER BY u.nombre_usuario, ca.orden;

-- Consulta 7 (VISTA + JOIN de 3): ¿Cómo terminó la carrera 1 en la partida de Sebastián?
SELECT v.posicion, p.nombre AS piloto, v.tiempo, v.puntos
FROM v_puntos v
JOIN piloto p   ON p.id_piloto   = v.id_piloto
JOIN carrera ca ON ca.id_carrera = v.id_carrera
WHERE v.id_partida = 1 AND ca.orden = 1
ORDER BY v.posicion;

-- Consulta 8 (SUBCONSULTA): ¿Qué usuarios tienen más presupuesto que el promedio?
SELECT u.nombre_usuario, pa.presupuesto
FROM partida pa
JOIN usuario u ON u.id_usuario = pa.id_usuario
WHERE pa.presupuesto > (SELECT AVG(presupuesto) FROM partida);

-- Consulta 9 (JOIN de 3 tablas + GROUP BY): ¿Cuántas carreras corrió cada usuario?
SELECT u.nombre_usuario, COUNT(DISTINCT r.id_carrera) AS carreras_corridas
FROM usuario u
JOIN partida pa ON pa.id_usuario = u.id_usuario
LEFT JOIN resultado r ON r.id_partida = pa.id_partida
GROUP BY u.nombre_usuario;

-- Consulta 10 (JOIN de 3 tablas + GROUP BY): ¿Cuál es el mejor tiempo de cada circuito?
SELECT ci.nombre AS circuito, MIN(r.tiempo) AS mejor_tiempo
FROM resultado r
JOIN carrera ca  ON ca.id_carrera  = r.id_carrera
JOIN circuito ci ON ci.id_circuito = ca.id_circuito
GROUP BY ci.nombre;


-- =====================================================================
-- 5. TRANSACCIÓN: COMPRAR UN COMPONENTE
-- Descontar la plata y registrar la compra tienen que pasar juntas.
-- =====================================================================

DELIMITER //
CREATE PROCEDURE sp_comprar_componente(IN p_partida INT, IN p_componente INT, IN p_carrera INT)
BEGIN
    DECLARE v_presupuesto DECIMAL(12,2);
    DECLARE v_costo DECIMAL(12,2);

    -- Si algo falla, se deshace todo
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'Compra cancelada: no se modificó nada' AS resultado;
    END;

    START TRANSACTION;

    SELECT presupuesto INTO v_presupuesto FROM partida WHERE id_partida = p_partida;
    SELECT costo INTO v_costo FROM componentes WHERE id_componentes = p_componente;

    IF v_presupuesto >= v_costo THEN
        UPDATE partida SET presupuesto = presupuesto - v_costo WHERE id_partida = p_partida;
        INSERT INTO compra (id_partida, id_componentes, id_carrera, precio_pagado)
        VALUES (p_partida, p_componente, p_carrera, v_costo);
        COMMIT;
        SELECT 'Compra realizada' AS resultado;
    ELSE
        ROLLBACK;
        SELECT 'Saldo insuficiente' AS resultado;
    END IF;
END //
DELIMITER ;

-- =====================================================================
-- 6. PROCEDIMIENTO: CORRER LA SIGUIENTE CARRERA
-- Lo llama la aplicación. NO se ejecuta acá porque usa RAND()
-- y cambiaría los datos de prueba en cada ejecución.
-- =====================================================================

DELIMITER //
CREATE PROCEDURE sp_correr_carrera(IN p_partida INT)
BEGIN
    DECLARE v_orden INT;
    DECLARE v_carrera INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'Error: la carrera no se registró' AS resultado;
    END;

    START TRANSACTION;

    -- 1. La próxima carrera es la siguiente a las que ya corrió (así se respeta el orden)
    SELECT COUNT(DISTINCT id_carrera) + 1 INTO v_orden
    FROM resultado WHERE id_partida = p_partida;

    SELECT c.id_carrera INTO v_carrera
    FROM carrera c
    JOIN partida pa ON pa.id_temporada = c.id_temporada
    WHERE pa.id_partida = p_partida AND c.orden = v_orden;

    IF v_carrera IS NULL THEN
        ROLLBACK;
        SELECT 'La temporada ya terminó' AS resultado;
    ELSE
        -- 2. Un tiempo por cada piloto contratado, con la fórmula del juego
        INSERT INTO resultado (tiempo, id_partida, id_carrera, id_piloto)
        SELECT ci.tiempo_base
               - p.habilidad * 0.05
               - (SELECT COALESCE(SUM(co.rendimiento_extra), 0)     -- componentes activos
                  FROM compra cm
                  JOIN componentes co ON co.id_componentes = cm.id_componentes
                  JOIN carrera cc ON cc.id_carrera = cm.id_carrera
                  WHERE cm.id_partida = p_partida
                    AND v_orden - cc.orden >= 0
                    AND v_orden - cc.orden < co.durabilidad)
               + RAND() * 1.5,                                       -- azar
               p_partida, v_carrera, p.id_piloto
        FROM contrato ct
        JOIN piloto p ON p.id_piloto = ct.id_piloto
        JOIN carrera c ON c.id_carrera = v_carrera
        JOIN circuito ci ON ci.id_circuito = c.id_circuito
        WHERE ct.id_partida = p_partida;

        -- 3. Si era la última carrera, la partida termina
        IF v_orden = (SELECT MAX(c.orden) FROM carrera c
                      JOIN partida pa ON pa.id_temporada = c.id_temporada
                      WHERE pa.id_partida = p_partida) THEN
            UPDATE partida SET estado = 1 WHERE id_partida = p_partida;
        END IF;

        COMMIT;
        SELECT 'Carrera corrida' AS resultado;
    END IF;
END //
DELIMITER ;


-- =====================================================================
-- 7. PRUEBAS DE LA TRANSACCIÓN (van al final: si la herramienta de importación
--    se detiene al mostrar resultados, los procedimientos ya quedaron creados)
-- =====================================================================

-- CASO A (COMMIT): Martín compra el Motor antes de la carrera 1.
-- Tiene 37.000.000 y el motor cuesta 5.000.000 → queda con 32.000.000.
CALL sp_comprar_componente(3, 1, 1);

-- CASO B (ROLLBACK): Lucía intenta comprar otra vez la Aerodinámica antes de la carrera 1.
-- El UPDATE descuenta la plata, pero el INSERT falla porque esa compra ya existe (UNIQUE).
-- El ROLLBACK devuelve la plata: Lucía sigue con 23.000.000.
CALL sp_comprar_componente(2, 2, 1);

SELECT id_partida, presupuesto FROM partida;