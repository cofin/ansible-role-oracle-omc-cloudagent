Rem
Rem $Header: empl/oracle.em.sgfm/source/agent/scripts/grantPrivileges.sql /st_emgc_pt-bosco2/4 2019/04/22 08:26:13 pkaliren Exp $
Rem
Rem grantPrivileges.sql
Rem
Rem Copyright (c) 2018, 2019, Oracle and/or its affiliates.
Rem All rights reserved.
Rem
Rem    NAME
Rem      grantPrivileges.sql - <one-line expansion of the name>
Rem
Rem    DESCRIPTION
Rem      <short description of component this file declares/defines>
Rem
Rem    NOTES
Rem      <other useful comments, qualifications, etc.>
Rem
Rem    BEGIN SQL_FILE_METADATA
Rem    SQL_SOURCE_FILE: empl/oracle.em.sgfm/source/agent/scripts/grantPrivileges.sql
Rem    SQL_SHIPPED_FILE:
Rem    SQL_PHASE:
Rem    SQL_STARTUP_MODE: NORMAL
Rem    SQL_IGNORABLE_ERRORS: NONE
Rem    END SQL_FILE_METADATA
Rem
Rem    MODIFIED   (MM/DD/YY)
Rem    pkaliren    03/18/19 - EMCMS-17617
Rem    mhtrived    02/20/19 - EMCMS-19502 - ORA-01219 is thrown while
Rem                           discovering physical mounted standby database
Rem                           fix.
Rem    spudukol    01/30/19 - Fixed Jira emcms-15756
Rem    spudukol    09/27/18 - Created
Rem
SET ECHO ON

SET SERVEROUTPUT ON

SET VERIFY OFF

SET LINESIZE 32767

SET FEEDBACK OFF

SET HEADING OFF

DECLARE
    role_exist               INTEGER;
    db_version               v$instance.version%TYPE;
    db_major_version         INTEGER;
    db_minor_version         INTEGER;
    db_sub_version           INTEGER;
    isdb_version_above_12    BOOLEAN;
    isdb_version_above_122   BOOLEAN;
    is_db_cdb                VARCHAR2(3);
    dbrole                   VARCHAR2(25);
    monuser                  VARCHAR2(25) := 'C##OMC_USER';
    number_of_grants_given   INTEGER;
    user_exist               INTEGER;
    management_pack_value    VARCHAR2(4000);
    number_of_editions       INTEGER;
    db_role                  VARCHAR2(25);
    invoked_by_ita           BOOLEAN;
    sql_stmt                 VARCHAR2(100) := 'SELECT CDB from v$database';
	-- added by Cody for EBS integration
    profile_exist            INTEGER;
    is_db_ebs                BOOLEAN;
    is_db_psoft              BOOLEAN;
    ebs_tbl_cnt              NUMBER;
    psoft_tbl_cnt            NUMBER;
    table_not_found EXCEPTION;
    PRAGMA exception_init ( table_not_found, -00942 );
BEGIN
    invoked_by_ita := true;
    SELECT
        version
    INTO db_version
    FROM
        v$instance;
	--dbms_output.Put_line ('Version: ' || db_version);
	/*
	db_version = 12.1.0.2.0
	db_major_version=12
	db_minor_version=1
	db_sub_version=2
	*/

    SELECT
        to_number(substr(db_version, 1, instr(db_version, '.', 1, 1) - 1)),
        to_number(substr(db_version, instr(db_version, '.', 1, 1) + 1, instr(db_version, '.', 1, 2) - instr(db_version, '.', 1, 1
        ) - 1)),
        to_number(substr(db_version, instr(db_version, '.', 1, 3) + 1, instr(db_version, '.', 1, 4) - instr(db_version, '.', 1, 3
        ) - 1))
    INTO
        db_major_version,
        db_minor_version,
        db_sub_version
    FROM
        dual;

	/*
	Skip if the DB version was < 11
	db_major_version=10
	db_version=10.2.0.1.0
	*/

    IF ( db_major_version < 11 ) THEN
		--dbms_output.Put_line ('ERROR: IM/ITA  is not supported for the DB Version: ' || db_major_version);
        raise_application_error(-00406, 'IM/ITA  is not supported for the DB Version: ' || db_major_version);
    END IF;

	/*Skip if DB Verison start with 11.1 ita is supported from 11.2 versions of db
	db_major_version=11
	db_minor_version=1
	db_version=11.1.0.1.0
	*/

    IF ( ( db_major_version < 12 ) AND ( db_minor_version < 2 ) ) THEN
		--dbms_output.Put_line ('ERROR: IM/ITA is not supported for the DB Version:' || db_version);
        raise_application_error(-00406, 'IM/ITA  is not supported for the DB Version: ' || db_major_version);
    END IF;

	/*
	Skip if DB Versions are  11.2.0.1 or 11.2.0.2 or 11.2.0.3 for ITA
	Skip if DB Version is 11.2.0.1 for IM
	db_major_version=11
	db_minor_version=2
	db_sub_version=1
	db_version=11.2.0.1.0
	*/

    IF ( invoked_by_ita AND ( db_major_version < 12 ) AND ( db_minor_version >= 2 ) AND ( db_sub_version < 4 ) ) THEN
	   --dbms_output.Put_line ('ERROR: ITA is not supported for the DB Version:' || db_version);
        raise_application_error(-00406, 'ITA  is not supported for the DB Version: ' || db_major_version);
    ELSIF ( ( db_major_version < 12 ) AND ( db_minor_version >= 2 ) AND ( db_sub_version < 2 ) ) THEN
	   --dbms_output.Put_line ('ERROR: IM is not supported for the DB Version:' || db_version);
        raise_application_error(-00406, 'IM  is not supported for the DB Version: ' || db_major_version);
    END IF;

    IF ( db_major_version > 11 ) THEN
        isdb_version_above_12 := true;
    ELSE
        isdb_version_above_12 := false;
    END IF;

    IF ( ( ( isdb_version_above_12 = true ) AND ( db_minor_version >= 2 ) ) OR ( db_major_version >= 18 ) ) THEN
        isdb_version_above_122 := true;
    ELSE
        isdb_version_above_122 := false;
    END IF;

	/*
	CDB column not available in 11 version of dbs, provide default value as 'NO'
	*/

    IF ( isdb_version_above_12 ) THEN
        EXECUTE IMMEDIATE sql_stmt
        INTO is_db_cdb;
        EXECUTE IMMEDIATE 'select nvl(max(upper(value)),''NONE'') from   v$parameter WHERE NAME=''control_management_pack_access'' AND con_id <= 1'
        INTO management_pack_value;
    ELSE
        is_db_cdb := 'NO';
        EXECUTE IMMEDIATE 'SELECT nvl(max(upper(value)),''NONE'') FROM v$parameter WHERE name=''control_management_pack_access'''
        INTO management_pack_value;
    END IF;
	--dbms_output.Put_line ('Enabled Pack: ' || management_pack_value);

    IF ( invoked_by_ita AND ( number_of_editions = 0 OR management_pack_value = 'NONE' ) ) THEN
        dbms_output.put_line('WARNING: ITA will only collect available performance metrics for Standard Edition databases.');
    END IF;

    EXECUTE IMMEDIATE 'SELECT sys_context(''USERENV'',''DATABASE_ROLE'') from dual'
    INTO db_role;
    IF ( invoked_by_ita AND db_role <> 'PRIMARY' ) THEN
        dbms_output.put_line('WARNING: ITA will not collect performance metrics for standby DB.');
    END IF;

    IF ( is_db_cdb = 'YES' ) THEN
        dbrole := 'c##omc_user_role';
    ELSIF ( is_db_cdb = 'NO' ) THEN
        dbrole := 'omc_user_role';
    END IF;

    -- SELECT
    --     COUNT(*)
    -- INTO profile_exist
    -- FROM
    --     dba_profiles
    -- WHERE
    --     profile = upper('SERVICE_ACCOUNT');

    -- IF ( profile_exist = 0 ) THEN
    --     dbms_output.put_line('create profile service_account');
    --     EXECUTE IMMEDIATE 'create profile service_account limit composite_limit default sessions_per_user default cpu_per_session default cpu_per_call default logical_reads_per_session default logical_reads_per_call default	idle_time default connect_time default private_sga default failed_login_attempts unlimited password_life_time unlimited	password_reuse_time unlimited password_reuse_max unlimited password_verify_function null password_lock_time unlimited password_grace_time unlimited'
    --     ;
    -- ELSIF ( profile_exist > 0 ) THEN
    --     dbms_output.put_line('alter profile service_account');
    --     EXECUTE IMMEDIATE 'alter profile service_account limit composite_limit default sessions_per_user default cpu_per_session default cpu_per_call default logical_reads_per_session default logical_reads_per_call default	idle_time default connect_time default private_sga default failed_login_attempts unlimited password_life_time unlimited	password_reuse_time unlimited password_reuse_max unlimited password_verify_function null password_lock_time unlimited password_grace_time unlimited'
    --     ;
    -- END IF;

    SELECT
        COUNT(*)
    INTO role_exist
    FROM
        dba_roles
    WHERE
        role = upper(dbrole);

    IF ( role_exist = 0 ) THEN
        dbms_output.put_line('create role ' || dbrole);
        EXECUTE IMMEDIATE 'create role '  || dbrole;
    END IF;

    SELECT
        COUNT(*)
    INTO user_exist
    FROM
        dba_users
    WHERE
        username = upper(monuser);


       /* Starting Basic  IM privileges */

    dbms_output.put_line('granting basic privs to ' || monuser);

	----dbms_output.Put_line ('granting create session to ' || monuser);
    EXECUTE IMMEDIATE 'grant create session to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$parameter to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$parameter to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$parameter to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$parameter to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$instance to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$instance to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$instance to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$instance to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$services to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$services to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$services to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$services to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$sql_monitor to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$sql_monitor to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$database to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$database to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$database to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$database to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$osstat to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$osstat to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$osstat to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$osstat to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$statname  to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$statname  to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$statname to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$statname  to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$sga to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$sga to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$pgastat to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$pgastat to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$sysmetric_summary to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$sysmetric_summary to ' || monuser;

	--dbms_output.Put_line ('granting select on sys.dba_tablespaces to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on sys.dba_tablespaces to ' || monuser;

	--dbms_output.Put_line ('granting select on dba_data_files to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on dba_data_files to ' || monuser;

	--dbms_output.Put_line ('granting select on dba_free_space to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on dba_free_space to ' || monuser;

	--dbms_output.Put_line ('granting select on dba_undo_extents to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on dba_undo_extents to ' || monuser;

	--dbms_output.Put_line ('granting select on dba_tablespace_usage_metrics to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on dba_tablespace_usage_metrics to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$active_session_history to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$active_session_history to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$active_session_history to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$active_session_history to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$ash_info to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$ash_info to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$ash_info to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$ash_info to ' || monuser;

	--dbms_output.Put_line ('granting select on dba_temp_files to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on dba_temp_files to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$sort_segment to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$sort_segment to ' || monuser;

	--dbms_output.Put_line ('granting select on sys.ts$ to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on sys.ts$ to ' || monuser;

	--dbms_output.Put_line ('granting execute on sys.dbms_lock to ' || monuser );
    EXECUTE IMMEDIATE 'grant execute on sys.dbms_lock to ' || monuser;

	--dbms_output.Put_line ('granting execute on dbms_system to ' || monuser );
    EXECUTE IMMEDIATE 'grant execute on dbms_system to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$session to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$session to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$session  to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$session  to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$sqlarea     to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$sqlarea     to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$sqlstats     to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$sqlstats     to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$sqlcommand to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$sqlcommand to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$IOSTAT_FILE to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$IOSTAT_FILE to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$sysstat to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$sysstat to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$sysstat to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$sysstat to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$sys_time_model to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$sys_time_model to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$event_name to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$event_name to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$waitclassmetric to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$waitclassmetric to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$sysmetric to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$sysmetric to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$sysmetric to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$sysmetric to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$sysmetric_history to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$sysmetric_history to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$sysmetric_history to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$sysmetric_history to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$system_event to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$system_event to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$system_event to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$system_event to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$sql to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$sql to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$alert_types to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$alert_types to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$threshold_types to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$threshold_types to ' || monuser;

	--dbms_output.Put_line ('granting select on GV_$CONTROLFILE to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on GV_$CONTROLFILE to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$log to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$log to ' || monuser;

	--dbms_output.Put_line ('granting select on GV_$CONTROLFILE_RECORD_SECTION to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on GV_$CONTROLFILE_RECORD_SECTION to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$archive_dest_status to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$archive_dest_status to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$rman_backup_job_details to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$rman_backup_job_details to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$backup_piece_details to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$backup_piece_details to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$backup_set_details to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$backup_set_details to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$recovery_file_dest to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$recovery_file_dest to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$flashback_database_log to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$flashback_database_log to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$rman_configuration to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$rman_configuration to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$archive_dest to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$archive_dest to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$dataguard_stats to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$dataguard_stats to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$logmnr_stats to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$logmnr_stats to ' || monuser;

	--dbms_output.Put_line ('granting select on dba_logmnr_session to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on dba_logmnr_session to ' || monuser;

	--dbms_output.Put_line ('granting select on gv_$asm_client to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on gv_$asm_client to ' || monuser;

	--dbms_output.Put_line ('granting select on DBA_SCHEDULER_JOB_RUN_DETAILS to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on DBA_SCHEDULER_JOB_RUN_DETAILS to ' || monuser;

	--dbms_output.Put_line ('granting select on dba_jobs to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on dba_jobs to ' || monuser;

	--dbms_output.Put_line ('granting select on DBA_SCHEDULER_JOBS to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on DBA_SCHEDULER_JOBS to ' || monuser;

	--dbms_output.Put_line ('granting select on sys."_CURRENT_EDITION_OBJ" to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on sys."_CURRENT_EDITION_OBJ" to ' || monuser;

	--dbms_output.Put_line ('granting select on sys."_BASE_USER" to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on sys."_BASE_USER" to ' || monuser;

	--dbms_output.Put_line ('granting select on dba_users to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on dba_users to ' || monuser;

	--dbms_output.Put_line ('granting select on dba_registry to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on dba_registry to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$option to ' || monuser );
    EXECUTE IMMEDIATE 'grant select on v_$option to ' || monuser;

	/* End of IM privileges */

	/* ITA related privileges */
    IF ( invoked_by_ita ) THEN
        dbms_output.put_line('granting ITA privs to ' || monuser);
        EXECUTE IMMEDIATE 'grant select ON sys.dba_hist_snapshot to ' || monuser;
        EXECUTE IMMEDIATE 'grant select ON sys.dba_hist_database_instance to ' || monuser;
        EXECUTE IMMEDIATE 'grant select ON sys.dba_hist_ic_client_stats to ' || monuser;
        EXECUTE IMMEDIATE 'grant select ON sys.dba_hist_sgastat to ' || monuser;
        EXECUTE IMMEDIATE 'grant select ON sys.dba_hist_pgastat to ' || monuser;
        EXECUTE IMMEDIATE 'grant select ON sys.dba_hist_osstat to ' || monuser;
        EXECUTE IMMEDIATE 'grant select ON sys.dba_hist_sys_time_model to ' || monuser;
        EXECUTE IMMEDIATE 'grant select ON sys.dba_hist_sysstat to ' || monuser;
        EXECUTE IMMEDIATE 'grant select ON sys.dba_hist_sga to ' || monuser;
        EXECUTE IMMEDIATE 'grant select ON sys.dba_hist_sqlstat to ' || monuser;
        EXECUTE IMMEDIATE 'grant select ON sys.dba_hist_sqltext to ' || monuser;
        EXECUTE IMMEDIATE 'grant select ON sys.dba_hist_system_event to ' || monuser;
        EXECUTE IMMEDIATE 'grant select ON sys.dba_hist_sysmetric_history to ' || monuser;
        EXECUTE IMMEDIATE 'grant select ON V_$SQL to ' || monuser;
        EXECUTE IMMEDIATE 'grant select ON GV_$SQLCOMMAND to ' || monuser;
        EXECUTE IMMEDIATE 'grant select ON V_$SQL_PLAN to ' || monuser;
        EXECUTE IMMEDIATE 'grant select ON GV_$SQL_PLAN to ' || monuser;
        EXECUTE IMMEDIATE 'grant select ON V_$RSRC_CONSUMER_GROUP to ' || monuser;
        EXECUTE IMMEDIATE 'grant select ON GV_$RSRC_CONSUMER_GROUP to ' || monuser;
    END IF;
	/* End of ITA related privileges */

       /* Privileges that can be added only for DBs above version 12 */

    IF ( isdb_version_above_12 ) THEN
        dbms_output.put_line('granting Oracle DB 12c+ privs to ' || monuser);
		--dbms_output.Put_line ('granting  select on v_$disk_restore_range to ' || monuser );
        EXECUTE IMMEDIATE 'grant select on v_$disk_restore_range to ' || monuser;

		--dbms_output.Put_line ('granting  select on v_$sbt_restore_range to ' || monuser );
        EXECUTE IMMEDIATE 'grant select on v_$sbt_restore_range to ' || monuser;

		--dbms_output.Put_line ('granting select on cdb_services to ' || monuser );
        EXECUTE IMMEDIATE 'grant select on cdb_services to ' || monuser;

		--dbms_output.Put_line ('granting select on cdb_tablespace_usage_metrics to ' || monuser );
        EXECUTE IMMEDIATE 'grant select on cdb_tablespace_usage_metrics to ' || monuser;

		--dbms_output.Put_line ('granting select on cdb_pdbs to ' || monuser );
        EXECUTE IMMEDIATE 'grant select on cdb_pdbs to ' || monuser;

		--dbms_output.Put_line ('granting select on v_$pdbs to ' || monuser );
        EXECUTE IMMEDIATE 'grant select on v_$pdbs to ' || monuser;

		--dbms_output.Put_line ('granting select on gv_$pdbs to ' || monuser );
        EXECUTE IMMEDIATE 'grant select on gv_$pdbs to ' || monuser;

		--dbms_output.Put_line ('granting select on gv_$containers to ' || monuser );
        EXECUTE IMMEDIATE 'grant select on gv_$containers to ' || monuser;

		--dbms_output.Put_line ('granting select on v_$containers to ' || monuser );
        EXECUTE IMMEDIATE 'grant select on v_$containers to ' || monuser;

		--dbms_output.Put_line ('granting select on cdb_tablespaces to ' || monuser );
        EXECUTE IMMEDIATE 'grant select on cdb_tablespaces to ' || monuser;

		--dbms_output.Put_line ('granting select on cdb_data_files to ' || monuser );
        EXECUTE IMMEDIATE 'grant select on cdb_data_files to ' || monuser;

		--dbms_output.Put_line ('granting select on cdb_temp_files to ' || monuser );
        EXECUTE IMMEDIATE 'grant select on cdb_temp_files to ' || monuser;

		--dbms_output.Put_line ('granting select on cdb_free_space to ' || monuser );
        EXECUTE IMMEDIATE 'grant select on cdb_free_space to ' || monuser;

		--dbms_output.Put_line ('granting select on cdb_undo_extents to ' || monuser );
        EXECUTE IMMEDIATE 'grant select on cdb_undo_extents to ' || monuser;

		--dbms_output.Put_line ('granting select on CDB_SCHEDULER_JOB_RUN_DETAILS to ' || monuser );
        EXECUTE IMMEDIATE 'grant select on CDB_SCHEDULER_JOB_RUN_DETAILS to ' || monuser;

		--dbms_output.Put_line ('granting select on cdb_jobs to ' || monuser );
        EXECUTE IMMEDIATE 'grant select on cdb_jobs to ' || monuser;

		--dbms_output.Put_line ('granting select on CDB_SCHEDULER_JOBS to ' || monuser );
        EXECUTE IMMEDIATE 'grant select on CDB_SCHEDULER_JOBS to ' || monuser;

		--dbms_output.Put_line ('granting select on cdb_invalid_objects to ' || monuser );
        EXECUTE IMMEDIATE 'grant select on cdb_invalid_objects to ' || monuser;

		--dbms_output.Put_line ('granting execute  on SYS.DBMS_DRS to ' || monuser );
        EXECUTE IMMEDIATE 'grant execute on SYS.DBMS_DRS to ' || monuser;

		--dbms_output.Put_line ('granting select on v_$dg_broker_config to ' || monuser );
        EXECUTE IMMEDIATE 'grant select on v_$dg_broker_config to ' || monuser;
        -- IF ( is_db_cdb = 'YES' ) THEN
        --     dbms_output.put_line('granting Oracle DB container DB privs to ' || monuser);
        --     EXECUTE IMMEDIATE 'alter user '
        --                       || monuser
        --                       || ' set container_data=all CONTAINER=CURRENT';
        -- END IF;
    END IF;
	/* END OF  Privileges that can be added only for DBs above version 12 */

        /* Privileges that can be added only for DBs above version 12.2 */

    IF ( isdb_version_above_122 ) THEN
        dbms_output.put_line('granting Oracle DB 12.2+ privs to ' || monuser);

		--dbms_output.Put_line ('granting read on v_$system_parameter to ' || monuser );
        EXECUTE IMMEDIATE 'grant read on v_$system_parameter to ' || monuser;

		--dbms_output.Put_line ('granting read on gv_$system_parameter to ' || monuser );
        EXECUTE IMMEDIATE 'grant read on gv_$system_parameter to ' || monuser;

		--dbms_output.Put_line ('granting read on v_$rsrcpdbmetric_history to ' || monuser );
        EXECUTE IMMEDIATE 'grant read on v_$rsrcpdbmetric_history to ' || monuser;

		--dbms_output.Put_line ('granting read on gv_$rsrcpdbmetric_history to ' || monuser );
        EXECUTE IMMEDIATE 'grant read on gv_$rsrcpdbmetric_history to ' || monuser;

		--dbms_output.Put_line ('granting read on v_$con_sysmetric_history to ' || monuser );
        EXECUTE IMMEDIATE 'grant read on v_$con_sysmetric_history to ' || monuser;

		--dbms_output.Put_line ('granting gv_$con_sysmetric_history to ' || monuser );
        EXECUTE IMMEDIATE 'grant read on gv_$con_sysmetric_history to ' || monuser;
    END IF;
	/* END OF Privileges that can be added only for DBs above version 12.2 */

    SELECT
        COUNT(1)
    INTO psoft_tbl_cnt
    FROM
        dba_all_tables
    WHERE
        table_name = upper('PSRELEASE');

    IF ( psoft_tbl_cnt > 0 ) THEN
        is_db_psoft := true;
        dbms_output.put_line('peoplesoft tables detected.');
    ELSE
        is_db_psoft := false;
        dbms_output.put_line('peoplesoft not detected');
    END IF;
	/* adding psoft privs */

    -- IF ( is_db_psoft ) THEN
    --     dbms_output.put_line('granting Peoplesoft permissions.');
    --     EXECUTE IMMEDIATE 'grant select on sysadm.psstatus to ' || monuser;
    --     EXECUTE IMMEDIATE 'grant select on sysadm.psrelease to ' || monuser;
    --     EXECUTE IMMEDIATE 'grant select on sysadm.pspmagent to ' || monuser;
    --     EXECUTE IMMEDIATE 'grant select on sysadm.ps_ptpmjmxuser to ' || monuser;
    --     EXECUTE IMMEDIATE 'grant select on sysadm.psibwsdldfn to ' || monuser;
    --     EXECUTE IMMEDIATE 'grant select on sysadm.psibsvcsetup to ' || monuser;
    --     EXECUTE IMMEDIATE 'grant select on sysadm.ps_ptsf_srch_engn to ' || monuser;
    --     EXECUTE IMMEDIATE 'CREATE OR REPLACE SYNONYM '
    --                       || monuser
    --                       || '."PSSTATUS" FOR "SYSADM"."PSSTATUS"';
    --     EXECUTE IMMEDIATE 'CREATE OR REPLACE SYNONYM '
    --                       || monuser
    --                       || '."PSRELEASE" FOR "SYSADM"."PSRELEASE"';
    --     EXECUTE IMMEDIATE 'CREATE OR REPLACE SYNONYM '
    --                       || monuser
    --                       || '."PSPMAGENT" FOR "SYSADM"."PSPMAGENT"';
    --     EXECUTE IMMEDIATE 'CREATE OR REPLACE SYNONYM '
    --                       || monuser
    --                       || '."PS_PTPMJMXUSER" FOR "SYSADM"."PS_PTPMJMXUSER"';
    --     EXECUTE IMMEDIATE 'CREATE OR REPLACE SYNONYM '
    --                       || monuser
    --                       || '."PSIBWSDLDFN" FOR "SYSADM"."PSIBWSDLDFN"';
    --     EXECUTE IMMEDIATE 'CREATE OR REPLACE SYNONYM '
    --                       || monuser
    --                       || '."PSIBSVCSETUP" FOR "SYSADM"."PSIBSVCSETUP"';
    --     EXECUTE IMMEDIATE 'CREATE OR REPLACE SYNONYM '
    --                       || monuser
    --                       || '."PS_PTSF_SRCH_ENGN" FOR "SYSADM"."PS_PTSF_SRCH_ENGN"';
    -- END IF;

    SELECT
        COUNT(1)
    INTO ebs_tbl_cnt
    FROM
        dba_all_tables
    WHERE
        table_name = upper('fnd_product_groups');

    IF ( ebs_tbl_cnt > 0 ) THEN
        is_db_ebs := true;
        dbms_output.put_line('ebs tables detected.');
    ELSE
        is_db_ebs := false;
        dbms_output.put_line('ebs not detected');
    END IF;

    /* adding ebs privs */

    IF ( is_db_ebs ) THEN
        dbms_output.put_line('granting EBS permissions.');
        --dbms_output.put_line('granting connect to ' || monuser);
        EXECUTE IMMEDIATE 'grant connect to ' || monuser;
				--dbms_output.put_line('granting select on ebs tables to ' || monuser);
        EXECUTE IMMEDIATE 'grant select on apps.fnd_oam_context_files to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_product_groups to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_conc_prog_onsite_info to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_concurrent_programs_vl to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_concurrent_requests to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_application_vl to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_concurrent_queues to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_lookups to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_concurrent_worker_requests to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_concurrent_worker_requests to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_concurrent_queues_vl to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_oam_fnduser_vl to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_form_sessions_v to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_cp_services to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_concurrent_processes to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_svc_components to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_log_messages to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_concurrent_programs to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_conflicts_domain to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_oracle_userid to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_app_servers to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_nodes to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.icx_sessions to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_user to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_responsibility to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.wf_deferred to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.wf_notification_in to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.wf_notification_out to  ' || monuser;

		/*dbms_output.put_line('granting execute on ebs packages to ' || monuser);*/
        EXECUTE IMMEDIATE 'grant execute on apps.fnd_oam_em to ' || monuser;
        EXECUTE IMMEDIATE 'grant execute on apps.fnd_profile to ' || monuser;
        EXECUTE IMMEDIATE 'grant execute on apps.fnd_web_config to  ' || monuser;
        EXECUTE IMMEDIATE 'grant execute on apps.fnd_web_sec to  ' || monuser;
        EXECUTE IMMEDIATE 'grant execute on apps.iby_creditcard_pkg to  ' || monuser;
        EXECUTE IMMEDIATE 'grant execute on apps.iby_security_pkg to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.iby_sys_security_options to  ' || monuser;
        EXECUTE IMMEDIATE 'create or replace synonym  '
                          || monuser
                          || '.iby_sys_security_options for apps.iby_sys_security_options';
        EXECUTE IMMEDIATE 'grant select on apps.fnd_user_preferences to  ' || monuser;
        EXECUTE IMMEDIATE 'create or replace synonym  '
                          || monuser
                          || '.fnd_user_preferences for apps.fnd_user_preferences';
        EXECUTE IMMEDIATE 'alter user '
                          || monuser
                          || ' enable editions';
        EXECUTE IMMEDIATE 'create or replace synonym  '
                          || monuser
                          || '.fnd_web_config for apps.fnd_web_config';
        EXECUTE IMMEDIATE 'create or replace synonym  '
                          || monuser
                          || '.iby_creditcard_pkg for apps.iby_creditcard_pkg';
        EXECUTE IMMEDIATE 'create or replace synonym  '
                          || monuser
                          || '.iby_security_pkg for apps.iby_security_pkg';
        EXECUTE IMMEDIATE 'create or replace synonym  '
                          || monuser
                          || '.fnd_web_sec for apps.fnd_web_sec';
        EXECUTE IMMEDIATE 'grant select on apps.fnd_profile_options to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_profile_option_values to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_profile_options_tl to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_user to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_application to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.fnd_nodes to  ' || monuser;
        EXECUTE IMMEDIATE 'grant select on apps.hr_operating_units to  ' || monuser;
        EXECUTE IMMEDIATE 'create or replace synonym  '
                          || monuser
                          || '.fnd_profile_options for apps.fnd_profile_options';
        EXECUTE IMMEDIATE 'create or replace synonym  '
                          || monuser
                          || '.fnd_profile_option_values for apps.fnd_profile_option_values';
        EXECUTE IMMEDIATE 'create or replace synonym  '
                          || monuser
                          || '.fnd_profile_options_tl for apps.fnd_profile_options_tl';
        EXECUTE IMMEDIATE 'create or replace synonym  '
                          || monuser
                          || '.fnd_user for apps.fnd_user';
        EXECUTE IMMEDIATE 'create or replace synonym  '
                          || monuser
                          || '.fnd_application for apps.fnd_application';
        EXECUTE IMMEDIATE 'create or replace synonym  '
                          || monuser
                          || '.fnd_responsibility for apps.fnd_responsibility';
        EXECUTE IMMEDIATE 'create or replace synonym  '
                          || monuser
                          || '.fnd_nodes for apps.fnd_nodes';
        EXECUTE IMMEDIATE 'create or replace synonym  '
                          || monuser
                          || '.hr_operating_units for apps.hr_operating_units';
    END IF;

	-- compliance grants

    dbms_output.put_line('granting permissions for config and compliance pack to ' || monuser);
    EXECUTE IMMEDIATE 'grant select on dba_tab_privs to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_profiles to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_role_privs to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on sys.link$ to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_users to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_users_with_defpwd to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_tab_privs to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_profiles to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_role_privs to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on sys.link$ to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_users to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_users_with_defpwd to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_db_links to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on v_$controlfile to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on v_$log to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_sys_privs to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_tables to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_external_tables to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_objects to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_sys_privs to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_roles to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on v_$encrypted_tablespaces to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on v_$tablespace to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_encrypted_columns to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_constraints to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_tab_privs to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_profiles to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_role_privs to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on sys.link$ to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_users to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_users_with_defpwd to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_db_links to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on v_$controlfile to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on v_$log to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_sys_privs to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_tables to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_external_tables to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_objects to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_sys_privs to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_roles to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on v_$encrypted_tablespaces to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on v_$tablespace to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_encrypted_columns to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_constraints to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_proxies to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_stmt_audit_opts to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_priv_audit_opts to ' || monuser;
    EXECUTE IMMEDIATE 'grant select on dba_obj_audit_opts to ' || monuser;
    EXECUTE IMMEDIATE 'grant '
                      || dbrole
                      || ' to '
                      || monuser;
    SELECT
        COUNT(*)
    INTO number_of_grants_given
    FROM
        (
            SELECT DISTINCT
                table_name,
                privilege
            FROM
                dba_role_privs rp
                JOIN role_tab_privs rtp ON ( rp.granted_role = rtp.role )
            WHERE
                rp.grantee = upper(monuser)
        );

    dbms_output.put_line(number_of_grants_given
                         || ' Grants given to user '
                         || monuser);
END;
/

EXIT;
