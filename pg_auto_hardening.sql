DO $_fn_anonima_$ 
DECLARE
    v_conf_record      RECORD;
    v_data_dir         TEXT := current_setting('data_directory');
    v_backup_cmd       TEXT;
    v_exec_wrapper     TEXT;
    
    -- Variables para diagnóstico
    v_ex_message       TEXT;
BEGIN
    -- 1. Configuración de entorno
    SET client_min_messages = notice;

    -- 2. Respaldo de seguridad
    BEGIN
        v_backup_cmd := format(
            'mkdir -p %1$s/backup_psql_conf && cp %1$s/postgresql.conf %1$s/backup_psql_conf/postgresql.conf_%2$s',
            v_data_dir,
            to_char(now(), 'YYYYMMDD')
        );
        
        EXECUTE format('COPY (SELECT 1) TO PROGRAM %L', v_backup_cmd);
        RAISE NOTICE 'CHECK: Respaldo de postgresql.conf creado exitosamente.';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_ex_message = MESSAGE_TEXT;
        RAISE EXCEPTION 'CRITICAL: Fallo al crear backup. Detalle: %', v_ex_message;
    END;

    -- 3. Aplicación de Hardening
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
            -- Ajuste en la construcción del comando SED para evitar fallos de shell
            -- Se usa comilla simple interna y se asegura espacio antes de v_data_dir
            format(
                'sed -i "s|^[[:space:]]*#*[[:space:]]*%1$s[[:space:]]*=.*|%1$s = ''%2$s''  # Hardened %3$s: &|" %4$s/postgresql.conf',
                s.name, 
                ts.target_val, 
                to_char(now(), 'YYYYMMDD'), 
                v_data_dir
            ) AS sed_command
        FROM pg_settings s
        JOIN target_settings ts ON s.name = ts.name
        WHERE s.setting <> ts.target_val
           OR (s.name = 'log_line_prefix' AND replace(s.setting, ' ', '') <> replace(ts.target_val, ' ', ''))
    LOOP
        BEGIN
            -- Se ejecuta el comando directamente
            EXECUTE format('COPY (SELECT 1) TO PROGRAM %L', v_conf_record.sed_command);
            RAISE NOTICE 'SUCCESS: Parámetro [%] actualizado.', v_conf_record.name;
            
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_ex_message = MESSAGE_TEXT;
            RAISE NOTICE 'ERROR: No se pudo modificar [%]. Detalle: %', v_conf_record.name, v_ex_message;
        END;
    END LOOP;

    -- 4. Recarga
    PERFORM pg_reload_conf();
    RAISE NOTICE 'PROCESS COMPLETE: Configuración recargada. Verifique logs del motor para parámetros que requieren reinicio.';

END $_fn_anonima_$;
