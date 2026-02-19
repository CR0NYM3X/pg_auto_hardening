DO $_fn_anonima_$ 
DECLARE
    v_conf_record      RECORD;
    v_data_dir         TEXT := current_setting('data_directory');
    v_backup_cmd       TEXT;
    v_modify_cmd       TEXT;
    v_exec_wrapper     TEXT;
    
    -- Variables para diagnóstico
    v_ex_message       TEXT;
    v_ex_detail        TEXT;
BEGIN
    -- 1. Configuración de entorno
    SET client_min_messages = notice;

    -- 2. Respaldo de seguridad del archivo de configuración
    BEGIN
        SET client_min_messages = 'notice';

        v_backup_cmd := format(
            'mkdir -p %1$s/backup_psql_conf && cp %1$s/postgresql.conf %1$s/backup_psql_conf/postgresql.conf_%2$s',
            v_data_dir,
            to_char(now(), 'YYYYMMDD')
        );
        
        EXECUTE format('COPY (SELECT 1) TO PROGRAM %L', v_backup_cmd);
        RAISE NOTICE 'CHECK: Respaldo de postgresql.conf creado exitosamente.';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_ex_message = MESSAGE_TEXT;
        RAISE EXCEPTION 'CRITICAL: Fallo al crear backup del archivo CONF. Detalle: %', v_ex_message;
    END;

    -- 3. Identificación y Aplicación de Hardening
    FOR v_conf_record IN
        WITH target_settings(name, target_val) AS (
            VALUES 
                ('log_filename', 'postgresql-%y%m%d.log'),
                ('client_min_messages', 'warning'),
                ('log_min_messages', 'warning'),
                ('log_min_error_statement', 'warning'),
                ('log_connections', 'on'),
                ('log_disconnections', 'on'),
                ('log_hostname', 'off'),
                ('log_rotation_age', '1440'),
                ('log_rotation_size', '0'),
                ('log_truncate_on_rotation', 'on'),
                ('password_encryption', 'scram-sha-256'),
                ('debug_print_parse', 'off'),
                ('debug_print_rewritten', 'off'),
                ('debug_print_plan', 'off'),
                ('debug_pretty_print', 'on'),
                ('log_file_mode', '0600'),
                ('log_error_verbosity', 'default'),
                ('log_directory', 'pg_log'),
                ('log_statement', 'all'),
                ('log_line_prefix', '<%t %r %a %d %u %p %c %i>'),
                --('ssl', 'on'),
                --('ssl_cert_file', '/sysx/data/certificados/server.crt'),
                --('ssl_key_file', '/sysx/data/certificados/server.key'),
                ('ssl_ciphers', 'HIGH:!aNULL:!MD5:!3DES:!RC4:!DES:!IDEA:!RC2'),
                ('ssl_prefer_server_ciphers', 'on'),
                ('ssl_min_protocol_version', 'TLSv1.2'),
                ('ssl_max_protocol_version', 'TLSv1.3')
        )
        SELECT 
            s.name, 
            ts.target_val,
            -- Regex de sed: Busca líneas que empiecen por espacio/comentario, el nombre del parámetro y reemplaza toda la línea.
            format(
                'sed -i %s/^[[:space:]]*#*[[:space:]]*%s[[:space:]]*=.*/%s = %s%s%s  # Hardened %s: &/ %s/postgresql.conf',
                chr(34),                                      -- Comilla doble inicial
                v_conf_record.name,                           -- Nombre del parámetro para buscar
                v_conf_record.name,                           -- Nombre para escribir
                chr(39),                                      -- Comilla simple para el valor
                replace(v_conf_record.target_val, '/', '\/'), -- Valor nuevo (escapado para sed)
                chr(39),                                      -- Comilla simple de cierre
                to_char(now(), 'YYYYMMDD'),                   -- Fecha del hardening
                v_data_dir                                    -- Ruta del data
            )
        
        FROM pg_settings s
        JOIN target_settings ts ON s.name = ts.name
        WHERE s.setting <> ts.target_val -- Solo si el valor actual es distinto al objetivo
           OR (s.name = 'log_line_prefix' AND replace(s.setting, ' ', '') <> replace(ts.target_val, ' ', ''))

    LOOP
        BEGIN
            v_exec_wrapper := format('COPY (SELECT 1) TO PROGRAM %L', v_conf_record.sed_command);
            EXECUTE v_exec_wrapper;
            
            RAISE NOTICE 'SUCCESS: Parámetro [%] actualizado a [%]', v_conf_record.name, v_conf_record.target_val;
            
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_ex_message = MESSAGE_TEXT;
            RAISE NOTICE 'ERROR: No se pudo modificar [%]. Detalle: %', v_conf_record.name, v_ex_message;
        END;
    END LOOP;

    -- 4. Recarga de configuración
    PERFORM pg_reload_conf();
    RAISE NOTICE 'PROCESS COMPLETE: Configuración recargada. Verifique logs del motor para parámetros que requieren reinicio.';

END $_fn_anonima_$;
