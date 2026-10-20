-- kpi: dotacion_activa
-- Dotación activa: Empleados sin fecha de baja al corte.
SELECT COUNT(*) AS valor
  FROM empleados
  WHERE fecha_baja IS NULL;

-- kpi: rotacion_anual
-- Rotación anual: Bajas del año divididas por la dotación promedio (inicio y fin de año).
SELECT ROUND(100.0 * (SELECT COUNT(*)
  FROM empleados
  WHERE fecha_baja BETWEEN :inicio_anio AND :corte) / (((SELECT COUNT(*)
  FROM empleados
  WHERE fecha_ingreso <= :corte_previo AND (fecha_baja IS NULL OR fecha_baja > :corte_previo)) + (SELECT COUNT(*)
  FROM empleados
  WHERE fecha_ingreso <= :corte AND (fecha_baja IS NULL OR fecha_baja > :corte))) / 2.0), 1) AS valor;

-- kpi: rotacion_mensual
-- Bajas por mes: Cantidad de bajas en cada mes del año de corte.
SELECT substr(fecha_baja, 1, 7) AS periodo, COUNT(*) AS valor
  FROM empleados
  WHERE fecha_baja BETWEEN :inicio_anio AND :corte
  GROUP BY 1
  ORDER BY 1;

-- kpi: dotacion_por_depto
-- Dotación por área: Empleados activos por departamento.
SELECT d.departamento AS categoria, COUNT(e.id_empleado) AS valor
  FROM (SELECT DISTINCT departamento
  FROM empleados) d
  LEFT JOIN empleados e ON e.departamento = d.departamento AND e.fecha_baja IS NULL
  GROUP BY d.departamento
  ORDER BY valor DESC, categoria;

-- kpi: antiguedad_promedio
-- Antigüedad promedio: Años promedio desde el ingreso hasta el corte, empleados activos.
SELECT ROUND(AVG((julianday(:corte) - julianday(fecha_ingreso)) / 365.25), 1) AS valor
  FROM empleados
  WHERE fecha_baja IS NULL;

-- kpi: salario_por_nivel
-- Salario promedio por nivel: Salario base promedio de los empleados activos de cada nivel.
SELECT 'N' || nivel AS categoria, ROUND(AVG(salario_base), 0) AS valor
  FROM empleados
  WHERE fecha_baja IS NULL
  GROUP BY nivel
  ORDER BY nivel;

-- kpi: compa_ratio
-- Compa-ratio promedio: Salario base dividido por el punto medio de la banda de su nivel; 1,00 es el punto medio.
SELECT ROUND(AVG(e.salario_base / ((b.minimo + b.maximo) / 2.0)), 2) AS valor
  FROM empleados e
  JOIN bandas b ON b.nivel = e.nivel
  WHERE e.fecha_baja IS NULL;

-- kpi: fuera_de_banda
-- Empleados fuera de banda: Porcentaje de activos con salario bajo el mínimo o sobre el máximo de su banda.
SELECT ROUND(100.0 * SUM(CASE WHEN e.salario_base < b.minimo OR e.salario_base > b.maximo THEN 1 ELSE 0 END) / COUNT(*), 1) AS valor
  FROM empleados e
  JOIN bandas b ON b.nivel = e.nivel
  WHERE e.fecha_baja IS NULL;

-- kpi: brecha_genero
-- Brecha salarial de género: Promedio simple de las brechas por nivel.
SELECT ROUND(AVG(brecha), 1) AS valor
  FROM (SELECT 100.0 * (AVG(CASE WHEN genero = 'M' THEN salario_base END) - AVG(CASE WHEN genero = 'F' THEN salario_base END)) / AVG(CASE WHEN genero = 'M' THEN salario_base END) AS brecha
  FROM empleados
  WHERE fecha_baja IS NULL
  GROUP BY nivel);

-- kpi: brecha_genero_nivel
-- Brecha salarial de género por nivel: (Salario promedio hombres − mujeres) / hombres, dentro de cada nivel. Es una brecha descriptiva, no un análisis de equidad ajustado.
SELECT 'N' || nivel AS categoria, ROUND(100.0 * (AVG(CASE WHEN genero = 'M' THEN salario_base END) - AVG(CASE WHEN genero = 'F' THEN salario_base END)) / AVG(CASE WHEN genero = 'M' THEN salario_base END), 1) AS valor
  FROM empleados
  WHERE fecha_baja IS NULL
  GROUP BY nivel
  ORDER BY nivel;

-- kpi: gasto_vs_presupuesto
-- Gasto real vs. presupuesto: Gasto salarial real dividido por el presupuestado, en los meses con gasto cerrado.
SELECT ROUND(100.0 * SUM(gasto_real) / SUM(presupuestado), 1) AS valor
  FROM presupuesto
  WHERE gasto_real IS NOT NULL;

-- kpi: presupuesto_anual
-- Presupuesto anual: Suma del presupuesto de los 12 meses de todas las áreas.
SELECT SUM(presupuestado) AS valor
  FROM presupuesto;

-- kpi: desviacion_por_depto
-- Desviación del gasto por área: (Gasto real − presupuestado) / presupuestado, por área, en los meses con gasto cerrado; positivo es sobregasto.
SELECT departamento AS categoria, ROUND(100.0 * (SUM(gasto_real) - SUM(presupuestado)) / SUM(presupuestado), 1) AS valor
  FROM presupuesto
  WHERE gasto_real IS NOT NULL
  GROUP BY departamento
  ORDER BY valor DESC, categoria;

-- kpi: gasto_mensual
-- Gasto salarial por mes: Gasto salarial real de cada mes cerrado, sumando todas las áreas.
SELECT mes AS periodo, SUM(gasto_real) AS valor
  FROM presupuesto
  WHERE gasto_real IS NOT NULL
  GROUP BY mes
  ORDER BY mes;

-- kpi: proyeccion_cierre
-- Proyección de cierre del año: Gasto real acumulado más el promedio de los últimos 3 meses cerrados por cada mes que falta. Es una proyección simple, no un modelo estadístico.
SELECT ROUND(SUM(gasto_real) + (SELECT AVG(gasto_mes)
  FROM (SELECT SUM(gasto_real) AS gasto_mes
  FROM presupuesto
  WHERE gasto_real IS NOT NULL
  GROUP BY mes
  ORDER BY mes DESC LIMIT 3)) * (SELECT COUNT(DISTINCT mes)
  FROM presupuesto
  WHERE gasto_real IS NULL), 0) AS valor
  FROM presupuesto
  WHERE gasto_real IS NOT NULL;

-- kpi: rotacion_temprana_pct
-- Bajas en los primeros 12 meses: Porcentaje de todas las bajas que ocurrieron con menos de 12 meses de antigüedad.
SELECT ROUND(100.0 * SUM(CASE WHEN julianday(fecha_baja) - julianday(fecha_ingreso) < 365 THEN 1 ELSE 0 END) / COUNT(*), 1) AS valor
  FROM empleados
  WHERE fecha_baja IS NOT NULL;

-- kpi: bajas_por_tramo
-- Bajas por tramo de antigüedad: Cantidad de bajas según la antigüedad al salir: T1 menos de 1 año, T2 de 1 a 3 años, T3 más de 3 años.
SELECT t.categoria AS categoria, COUNT(e.id_empleado) AS valor
  FROM (SELECT 'T1' AS categoria UNION ALL SELECT 'T2' UNION ALL SELECT 'T3') t
  LEFT JOIN empleados e ON e.fecha_baja IS NOT NULL AND CASE WHEN (julianday(e.fecha_baja) - julianday(e.fecha_ingreso)) / 365.25 < 1 THEN 'T1' WHEN (julianday(e.fecha_baja) - julianday(e.fecha_ingreso)) / 365.25 < 3 THEN 'T2' ELSE 'T3' END = t.categoria
  GROUP BY t.categoria
  ORDER BY t.categoria;

-- kpi: rotacion_por_depto
-- Bajas del año por área: Cantidad de bajas del año de corte en cada área.
SELECT d.departamento AS categoria, COUNT(e.id_empleado) AS valor
  FROM (SELECT DISTINCT departamento
  FROM empleados) d
  LEFT JOIN empleados e ON e.departamento = d.departamento AND e.fecha_baja BETWEEN :inicio_anio AND :corte
  GROUP BY d.departamento
  ORDER BY valor DESC, categoria;
