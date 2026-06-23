
-- sE DEFINENE LAS VARIABLES BIND

VARIABLE v_periodo VARCHAR2(6);
VARIABLE v_limite NUMBER;

--SE UTILIZAN LAS ASESORIAS DE JUNIO 2021 POR ENUNCIADO
BEGIN
    :v_periodo := '062021';
    --LIMITE DE ASIGNACIONES
    :v_limite := 250000;
END;
/
--SE UTILIZO para encontrar errores, se puede quitar
SET SERVEROUTPUT ON;

DECLARE

   
    -- Excepcion para limites de asignaciones
   
    ex_limite_asignacion EXCEPTION;


    -- VARRAY de porcentajes de movilizacion por comuna
 
    TYPE t_movil IS VARRAY(5) OF NUMBER;
    v_movil t_movil := t_movil(2,4,5,7,9);


    -- VARIABLES

    v_num_asesorias     NUMBER := 0;
    v_total_honorarios  NUMBER := 0;

    v_porc_contrato     NUMBER := 0;
    v_porc_profesion    NUMBER := 0;

    v_asig_movil        NUMBER := 0;
    v_asig_contrato     NUMBER := 0;
    v_asig_profesion    NUMBER := 0;

    v_total_asig        NUMBER := 0;


    -- CURSOR para seleccionar profesionales, elimina duplicados para juntar las asesorias de la misma persona y evitar problemas con pk al haceer join

    CURSOR c_profesionales IS
SELECT DISTINCT
    p.numrun_prof,
    p.nombre,
    p.appaterno,
    p.sueldo,
    p.cod_profesion,
    p.cod_tpcontrato,
    pr.nombre_profesion,
    c.nom_comuna
FROM profesional p
JOIN profesion pr ON p.cod_profesion = pr.cod_profesion
JOIN comuna c ON p.cod_comuna = c.cod_comuna
JOIN asesoria a ON a.numrun_prof = p.numrun_prof
WHERE TO_CHAR(a.inicio_asesoria,'MMYYYY') = :v_periodo
ORDER BY pr.nombre_profesion, p.appaterno, p.nombre;

BEGIN


    -- trunc de tablas para ejecutar nuevamente

    EXECUTE IMMEDIATE 'TRUNCATE TABLE detalle_asignacion_mes';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE resumen_mes_profesion';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE errores_proceso';


    -- SECUENCIA, se elimina al comenzar el proceso nuevamente, si es la primera vez ignora el error

    BEGIN
        EXECUTE IMMEDIATE 'DROP SEQUENCE sq_error';
    EXCEPTION
        WHEN OTHERS THEN NULL;
    END;

    EXECUTE IMMEDIATE 'CREATE SEQUENCE sq_error START WITH 1';

 
    -- LOOP recorre todos los profesionales del cursor
  
    FOR r IN c_profesionales LOOP
--inicializa variables 
        v_asig_movil := 0;
        v_asig_contrato := 0;
        v_asig_profesion := 0;
        v_total_asig := 0;


        -- ASESORÍAS, calcula cantidad de asesorias por profesional y la suma de los honorarios de ellas
      
        SELECT COUNT(*)
        INTO v_num_asesorias
        FROM asesoria
        WHERE numrun_prof = r.numrun_prof
          AND TO_CHAR(inicio_asesoria,'MMYYYY') = :v_periodo;

        SELECT NVL(SUM(honorario),0)
        INTO v_total_honorarios
        FROM asesoria
        WHERE numrun_prof = r.numrun_prof
          AND TO_CHAR(inicio_asesoria,'MMYYYY') = :v_periodo;

  
        -- MOVILIZACIÓN, agrega la asginacion por movilizacion dependiendo de la comuna
      
        IF r.nom_comuna = 'Santiago' AND v_total_honorarios < 350000 THEN
            v_asig_movil := ROUND(v_total_honorarios * v_movil(1)/100);
--ñuñua aparece con problemas de codificacion en consolo pero no hay errores al usar la ñ en filtro
        ELSIF r.nom_comuna = 'Ñuñoa' THEN
            v_asig_movil := ROUND(v_total_honorarios * v_movil(2)/100);

        ELSIF r.nom_comuna = 'La Reina' AND v_total_honorarios < 400000 THEN
            v_asig_movil := ROUND(v_total_honorarios * v_movil(3)/100);

        ELSIF r.nom_comuna = 'La Florida' AND v_total_honorarios < 800000 THEN
            v_asig_movil := ROUND(v_total_honorarios * v_movil(4)/100);

        ELSIF r.nom_comuna = 'Macul' AND v_total_honorarios < 680000 THEN
            v_asig_movil := ROUND(v_total_honorarios * v_movil(5)/100);
        END IF;

     
        -- TIPO CONTRATO, calcula asignacion por contrato segun el tipo
      
        SELECT incentivo
        INTO v_porc_contrato
        FROM tipo_contrato
        WHERE cod_tpcontrato = r.cod_tpcontrato;

        v_asig_contrato := ROUND(v_total_honorarios * v_porc_contrato / 100);

     
        -- PROFESIÓN, calcula asignacion segun porcentaje por profesion, maneja el error de porcentajes faltantes en 2
      
        BEGIN
            SELECT asignacion
            INTO v_porc_profesion
            FROM porcentaje_profesion
            WHERE cod_profesion = r.cod_profesion;

            v_asig_profesion := ROUND(r.sueldo * v_porc_profesion / 100);

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                INSERT INTO errores_proceso
                VALUES (
                    sq_error.NEXTVAL,
                    'ORA-01403 No se ha encontrado ningún dato',
                    'Error al obtener porcentaje de asignación para el run Nro. ' || r.numrun_prof
                );
                v_asig_profesion := 0;
        END;

 
        -- TOTAL de asignaciones, maneja nulls en caso de
      
        v_total_asig :=
            NVL(v_asig_movil,0) +
            NVL(v_asig_contrato,0) +
            NVL(v_asig_profesion,0);

     
        -- LÍMITE, maneja errores en caso de que las asignaciones superen el limite, reemplaza por el valor correspondiente
    
        IF v_total_asig > :v_limite THEN
            INSERT INTO errores_proceso
            VALUES (
                sq_error.NEXTVAL,
                'TOPE_ SUPERADO',
                'Se reemplazo el monto total de las asignaciones calculadas de ' || v_total_asig || ' por el monto de 250000 para el run Nro ' || r.numrun_prof
            );
            v_total_asig := :v_limite;
        END IF;

   
        -- Tabla detalle con formato correspondiente
      
        INSERT INTO detalle_asignacion_mes
        VALUES (
            6,
            2021,
            TO_CHAR(r.numrun_prof),
            UPPER(r.appaterno || ' ' || r.nombre),
            INITCAP(r.nombre_profesion),
            v_num_asesorias,
            v_total_honorarios,
            v_asig_movil,
            v_asig_contrato,
            v_asig_profesion,
            v_total_asig
        );

    END LOOP;


    -- RESUMEN de asignaciones y  honorarios por profesion  con formato

    INSERT INTO resumen_mes_profesion
    SELECT
        202106,
        INITCAP(profesion),
        SUM(nro_asesorias),
        SUM(monto_honorarios),
        SUM(monto_movil_extra),
        SUM(monto_asig_tipocont),
        SUM(monto_asig_profesion),
        SUM(monto_total_asignaciones)
    FROM detalle_asignacion_mes
    GROUP BY profesion;

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE(SQLERRM);
END;
/
--selects para revisar tablas
SELECT *
FROM detalle_asignacion_mes;
SELECT *
FROM resumen_mes_profesion;
SELECT *
FROM errores_proceso;
