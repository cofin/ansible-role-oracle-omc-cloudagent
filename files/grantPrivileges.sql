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

set echo on
set serveroutput on
set verify off
set linesize 32767
set feedback off
set heading off

declare
	role_exist integer;
	db_version v$instance.version%type;
	db_major_version INTEGER;
	db_minor_version INTEGER;
	db_sub_version INTEGER;
	isdb_version_above_12 BOOLEAN;
	isdb_version_above_122 BOOLEAN;
	is_db_cdb varchar2(3);
	dbrole varchar2(25);
	monuser varchar2(25);
	number_Of_grants_given INTEGER;
	user_exist integer;
	management_pack_value VARCHAR2(4000);
	number_of_editions INTEGER;
	db_role varchar2(25);
	invoked_by_ita BOOLEAN;
	sql_stmt varchar2 ( 100 ) := 'SELECT CDB from v$database';
	-- added by Cody for EBS integration
	is_db_ebs boolean;
	ebs_tbl_cnt number;
    table_not_found EXCEPTION;
    PRAGMA exception_init ( table_not_found, -00942 );

begin
	if ('&3' ='Y') then
		invoked_by_ita := TRUE;
	else
		invoked_by_ita := FALSE;
	end if;
	select version into db_version from v$instance;
	--dbms_output.Put_line ('Version: ' || db_version);
	/*
	db_version = 12.1.0.2.0
	db_major_version=12
	db_minor_version=1
	db_sub_version=2
	*/
    SELECT to_number(SUBSTR(db_version,
                            1,
                            Instr(db_version, '.', 1, 1)-1 )) ,
           to_number(SUBSTR(db_version,
                            Instr(db_version, '.', 1, 1)+1 ,
                            Instr(db_version, '.', 1, 2) - Instr(db_version, '.', 1, 1)-1)),
	   to_number(SUBSTR(db_version,
                            Instr(db_version, '.', 1, 3)+1 ,
                            Instr(db_version, '.', 1, 4) - Instr(db_version, '.', 1, 3)-1))
	into db_major_version, db_minor_version , db_sub_version
    FROM DUAL;

	/*
	Skip if the DB version was < 11
	db_major_version=10
	db_version=10.2.0.1.0
	*/
	if (db_major_version < 11) then
		--dbms_output.Put_line ('ERROR: IM/ITA  is not supported for the DB Version: ' || db_major_version);
		RAISE_APPLICATION_ERROR(-00406, 'IM/ITA  is not supported for the DB Version: ' || db_major_version);
	end if;

	/*Skip if DB Verison start with 11.1 ita is supported from 11.2 versions of db
	db_major_version=11
	db_minor_version=1
	db_version=11.1.0.1.0
	*/
	if ((db_major_version < 12) and (db_minor_version < 2)) then
		--dbms_output.Put_line ('ERROR: IM/ITA is not supported for the DB Version:' || db_version);
		RAISE_APPLICATION_ERROR(-00406, 'IM/ITA  is not supported for the DB Version: ' || db_major_version);
	end if;

	/*
	Skip if DB Versions are  11.2.0.1 or 11.2.0.2 or 11.2.0.3 for ITA
	Skip if DB Version is 11.2.0.1 for IM
	db_major_version=11
	db_minor_version=2
	db_sub_version=1
	db_version=11.2.0.1.0
	*/
	if ( invoked_by_ita and (db_major_version < 12) and (db_minor_version >= 2) and (db_sub_version < 4)) then
	   --dbms_output.Put_line ('ERROR: ITA is not supported for the DB Version:' || db_version);
	   RAISE_APPLICATION_ERROR(-00406, 'ITA  is not supported for the DB Version: ' || db_major_version);
	elsif ((db_major_version < 12) and (db_minor_version >= 2) and (db_sub_version < 2)) then
	   --dbms_output.Put_line ('ERROR: IM is not supported for the DB Version:' || db_version);
	   RAISE_APPLICATION_ERROR(-00406, 'IM  is not supported for the DB Version: ' || db_major_version);
	end if;

	if (db_major_version > 11) then
		isdb_version_above_12 := true;
	else
		isdb_version_above_12 := false;
	end if;

	if (((isdb_version_above_12 = true) and (db_minor_version >= 2))	or ( db_major_version >= 18 )) then
		isdb_version_above_122 := true;
	else
	  isdb_version_above_122 := false;
	end if;

	/*
	CDB column not available in 11 version of dbs, provide default value as 'NO'
	*/
	if (isdb_version_above_12 ) then
	   execute immediate sql_stmt into is_db_cdb ;
	   execute immediate 'select nvl(max(upper(value)),''NONE'') from   v$parameter WHERE NAME=''control_management_pack_access'' AND con_id <= 1' into management_pack_value;
	else
		is_db_cdb := 'NO';
		execute immediate 'SELECT nvl(max(upper(value)),''NONE'') FROM v$parameter WHERE name=''control_management_pack_access''' into management_pack_value;
	end if;
	--dbms_output.Put_line ('Enabled Pack: ' || management_pack_value);

	if (invoked_by_ita and (number_of_editions = 0 or management_pack_value = 'NONE')) then
		dbms_output.Put_line('WARNING: ITA will only collect available performance metrics for Standard Edition databases.');
	end if;

	execute immediate 'SELECT sys_context(''USERENV'',''DATABASE_ROLE'') from dual' into 	db_role;
	if	(invoked_by_ita and db_role <> 'PRIMARY') then
		dbms_output.Put_line('WARNING: ITA will not collect performance metrics for standby DB.');
	end if;

	if (is_db_cdb = 'YES') then
		dbrole := 'c##omc_mon_role';
		if(length('&1')>2 and upper(substr('&1',1,3)) <> 'C##') then
			monuser := 'c##&1';
			--dbms_output.Put_line ('WARNING: Provided database details were CDB database, so user will be created with c## prefix.');
		else
			monuser := '&1';
		end if;
	elsif (is_db_cdb = 'NO') then
		dbrole := 'omc_mon_role';
		monuser := '&1';
	end if;

	select count(*) into role_exist from dba_roles where role=upper(dbrole);
	if (role_exist = 0) then
		dbms_output.Put_line ('create role ' || dbrole);

		execute immediate 'create role ' || dbrole;
	end if;

	select count(*) into user_exist from dba_users where username=upper(monuser);
	if (user_exist = 0) then
		dbms_output.Put_line ('creating user ' || monuser);

		execute immediate 'create user ' || monuser || ' identified by "&2"';
	elsif (user_exist > 0) then
		dbms_output.Put_line ('altering account ' || monuser);

		execute immediate 'alter user ' || monuser || ' profile serviceaccount account unlock identified by "&2"';
	end if;

       /* Starting Basic  IM privileges */
	dbms_output.Put_line ('granting basic privs to ' || dbrole);

	----dbms_output.Put_line ('granting create session to ' || monuser);
	execute immediate 'grant create session to ' || monuser;

	--dbms_output.Put_line ('granting select on v_$parameter to ' || dbrole );
	execute immediate 'grant select on v_$parameter to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$parameter to ' || dbrole );
	execute immediate 'grant select on gv_$parameter to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$instance to ' || dbrole );
	execute immediate 'grant select on v_$instance to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$instance to ' || dbrole );
	execute immediate 'grant select on gv_$instance to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$services to ' || dbrole );
	execute immediate 'grant select on gv_$services to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$services to ' || dbrole );
	execute immediate 'grant select on v_$services to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$sql_monitor to ' || dbrole );
	execute immediate 'grant select on gv_$sql_monitor to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$database to ' || dbrole );
	execute immediate 'grant select on v_$database to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$database to ' || dbrole );
	execute immediate 'grant select on gv_$database to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$osstat to ' || dbrole );
	execute immediate 'grant select on v_$osstat to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$osstat to ' || dbrole );
	execute immediate 'grant select on gv_$osstat to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$statname  to ' || dbrole );
	execute immediate 'grant select on v_$statname  to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$statname to ' || dbrole );
	execute immediate 'grant select on gv_$statname  to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$sga to ' || dbrole );
	execute immediate 'grant select on gv_$sga to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$pgastat to ' || dbrole );
	execute immediate 'grant select on gv_$pgastat to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$sysmetric_summary to ' || dbrole );
	execute immediate 'grant select on gv_$sysmetric_summary to ' || dbrole;

	--dbms_output.Put_line ('granting select on sys.dba_tablespaces to ' || dbrole );
	execute immediate 'grant select on sys.dba_tablespaces to ' || dbrole;

	--dbms_output.Put_line ('granting select on dba_data_files to ' || dbrole );
	execute immediate 'grant select on dba_data_files to ' || dbrole;

	--dbms_output.Put_line ('granting select on dba_free_space to ' || dbrole );
	execute immediate 'grant select on dba_free_space to ' || dbrole;

	--dbms_output.Put_line ('granting select on dba_undo_extents to ' || dbrole );
	execute immediate 'grant select on dba_undo_extents to ' || dbrole;

	--dbms_output.Put_line ('granting select on dba_tablespace_usage_metrics to ' || dbrole );
	execute immediate 'grant select on dba_tablespace_usage_metrics to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$active_session_history to ' || dbrole );
	execute immediate 'grant select on v_$active_session_history to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$active_session_history to ' || dbrole );
	execute immediate 'grant select on gv_$active_session_history to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$ash_info to ' || dbrole );
	execute immediate 'grant select on v_$ash_info to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$ash_info to ' || dbrole );
	execute immediate 'grant select on gv_$ash_info to ' || dbrole;

	--dbms_output.Put_line ('granting select on dba_temp_files to ' || dbrole );
	execute immediate 'grant select on dba_temp_files to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$sort_segment to ' || dbrole );
	execute immediate 'grant select on gv_$sort_segment to ' || dbrole;

	--dbms_output.Put_line ('granting select on sys.ts$ to ' || dbrole );
	execute immediate 'grant select on sys.ts$ to ' || dbrole;

	--dbms_output.Put_line ('granting execute on sys.dbms_lock to ' || dbrole );
	execute immediate 'grant execute on sys.dbms_lock to ' || dbrole;

	--dbms_output.Put_line ('granting execute on dbms_system to ' || dbrole );
	execute immediate 'grant execute on dbms_system to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$session to ' || dbrole );
	execute immediate 'grant select on v_$session to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$session  to ' || dbrole );
	execute immediate 'grant select on gv_$session  to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$sqlarea     to ' || dbrole );
	execute immediate 'grant select on gv_$sqlarea     to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$sqlstats     to ' || dbrole );
	execute immediate 'grant select on gv_$sqlstats     to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$sqlcommand to ' || dbrole );
	execute immediate 'grant select on v_$sqlcommand to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$IOSTAT_FILE to ' || dbrole );
	execute immediate 'grant select on gv_$IOSTAT_FILE to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$sysstat to ' || dbrole );
	execute immediate 'grant select on v_$sysstat to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$sysstat to ' || dbrole );
	execute immediate 'grant select on gv_$sysstat to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$sys_time_model to ' || dbrole );
	execute immediate 'grant select on gv_$sys_time_model to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$event_name to ' || dbrole );
	execute immediate 'grant select on v_$event_name to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$waitclassmetric to ' || dbrole );
	execute immediate 'grant select on gv_$waitclassmetric to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$sysmetric to ' || dbrole );
	execute immediate 'grant select on v_$sysmetric to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$sysmetric to ' || dbrole );
	execute immediate 'grant select on gv_$sysmetric to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$sysmetric_history to ' || dbrole );
	execute immediate 'grant select on v_$sysmetric_history to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$sysmetric_history to ' || dbrole );
	execute immediate 'grant select on gv_$sysmetric_history to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$system_event to ' || dbrole );
	execute immediate 'grant select on v_$system_event to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$system_event to ' || dbrole );
	execute immediate 'grant select on gv_$system_event to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$sql to ' || dbrole );
	execute immediate 'grant select on gv_$sql to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$alert_types to ' || dbrole );
	execute immediate 'grant select on v_$alert_types to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$threshold_types to ' || dbrole );
	execute immediate 'grant select on v_$threshold_types to ' || dbrole;

	--dbms_output.Put_line ('granting select on GV_$CONTROLFILE to ' || dbrole );
	execute immediate 'grant select on GV_$CONTROLFILE to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$log to ' || dbrole );
	execute immediate 'grant select on gv_$log to ' || dbrole;

	--dbms_output.Put_line ('granting select on GV_$CONTROLFILE_RECORD_SECTION to ' || dbrole );
	execute immediate 'grant select on GV_$CONTROLFILE_RECORD_SECTION to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$archive_dest_status to ' || dbrole );
	execute immediate 'grant select on v_$archive_dest_status to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$rman_backup_job_details to ' || dbrole );
	execute immediate 'grant select on v_$rman_backup_job_details to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$backup_piece_details to ' || dbrole );
	execute immediate 'grant select on v_$backup_piece_details to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$backup_set_details to ' || dbrole );
	execute immediate 'grant select on v_$backup_set_details to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$recovery_file_dest to ' || dbrole );
	execute immediate 'grant select on v_$recovery_file_dest to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$flashback_database_log to ' || dbrole );
	execute immediate 'grant select on v_$flashback_database_log to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$rman_configuration to ' || dbrole );
	execute immediate 'grant select on v_$rman_configuration to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$archive_dest to ' || dbrole );
	execute immediate 'grant select on v_$archive_dest to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$dataguard_stats to ' || dbrole );
	execute immediate 'grant select on v_$dataguard_stats to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$logmnr_stats to ' || dbrole );
	execute immediate 'grant select on v_$logmnr_stats to ' || dbrole;

	--dbms_output.Put_line ('granting select on dba_logmnr_session to ' || dbrole );
	execute immediate 'grant select on dba_logmnr_session to ' || dbrole;

	--dbms_output.Put_line ('granting select on gv_$asm_client to ' || dbrole );
	execute immediate 'grant select on gv_$asm_client to ' || dbrole;

	--dbms_output.Put_line ('granting select on DBA_SCHEDULER_JOB_RUN_DETAILS to ' || dbrole );
	execute immediate 'grant select on DBA_SCHEDULER_JOB_RUN_DETAILS to ' || dbrole;

	--dbms_output.Put_line ('granting select on dba_jobs to ' || dbrole );
	execute immediate 'grant select on dba_jobs to ' || dbrole;

	--dbms_output.Put_line ('granting select on DBA_SCHEDULER_JOBS to ' || dbrole );
	execute immediate 'grant select on DBA_SCHEDULER_JOBS to ' || dbrole;


	--dbms_output.Put_line ('granting select on sys."_CURRENT_EDITION_OBJ" to ' || dbrole );
	execute immediate 'grant select on sys."_CURRENT_EDITION_OBJ" to ' || dbrole;

	--dbms_output.Put_line ('granting select on sys."_BASE_USER" to ' || dbrole );
	execute immediate 'grant select on sys."_BASE_USER" to ' || dbrole;

	--dbms_output.Put_line ('granting select on dba_users to ' || dbrole );
	execute immediate 'grant select on dba_users to ' || dbrole;

	--dbms_output.Put_line ('granting select on dba_registry to ' || dbrole );
	execute immediate 'grant select on dba_registry to ' || dbrole;

	--dbms_output.Put_line ('granting select on v_$option to ' || dbrole );
	execute immediate 'grant select on v_$option to ' || dbrole;


	/* End of IM privileges */

	/* ITA related privileges */
	if(invoked_by_ita) then
		dbms_output.Put_line ('granting ITA privs to ' || dbrole);
		execute immediate 'grant select ON sys.dba_hist_snapshot to ' || dbrole;
		execute immediate 'grant select ON sys.dba_hist_database_instance to ' || dbrole;
		execute immediate 'grant select ON sys.dba_hist_ic_client_stats to ' || dbrole;
		execute immediate 'grant select ON sys.dba_hist_sgastat to ' || dbrole;
		execute immediate 'grant select ON sys.dba_hist_pgastat to ' || dbrole;
		execute immediate 'grant select ON sys.dba_hist_osstat to ' || dbrole;
		execute immediate 'grant select ON sys.dba_hist_sys_time_model to ' || dbrole;
		execute immediate 'grant select ON sys.dba_hist_sysstat to ' || dbrole;
		execute immediate 'grant select ON sys.dba_hist_sga to ' || dbrole;
		execute immediate 'grant select ON sys.dba_hist_sqlstat to ' || dbrole;
		execute immediate 'grant select ON sys.dba_hist_sqltext to ' || dbrole;
		execute immediate 'grant select ON sys.dba_hist_system_event to ' || dbrole;
		execute immediate 'grant select ON sys.dba_hist_sysmetric_history to ' || dbrole;
		execute immediate 'grant select ON V_$SQL to ' || dbrole;
		execute immediate 'grant select ON GV_$SQLCOMMAND to ' || dbrole;
		execute immediate 'grant select ON V_$SQL_PLAN to ' || dbrole;
		execute immediate 'grant select ON GV_$SQL_PLAN to ' || dbrole;
		execute immediate 'grant select ON V_$RSRC_CONSUMER_GROUP to ' || dbrole;
		execute immediate 'grant select ON GV_$RSRC_CONSUMER_GROUP to ' || dbrole;
	end if;
	/* End of ITA related privileges */


       /* Privileges that can be added only for DBs above version 12 */
	if (isdb_version_above_12) then
		dbms_output.Put_line ('granting Oracle DB 12c+ privs to ' || dbrole);
		--dbms_output.Put_line ('granting  select on v_$disk_restore_range to ' || dbrole );
		execute immediate 'grant select on v_$disk_restore_range to ' || dbrole;

		--dbms_output.Put_line ('granting  select on v_$sbt_restore_range to ' || dbrole );
		execute immediate 'grant select on v_$sbt_restore_range to ' || dbrole;

		--dbms_output.Put_line ('granting select on cdb_services to ' || dbrole );
		execute immediate 'grant select on cdb_services to ' || dbrole;

		--dbms_output.Put_line ('granting select on cdb_tablespace_usage_metrics to ' || dbrole );
		execute immediate 'grant select on cdb_tablespace_usage_metrics to ' || dbrole;

		--dbms_output.Put_line ('granting select on cdb_pdbs to ' || dbrole );
		execute immediate 'grant select on cdb_pdbs to ' || dbrole;

		--dbms_output.Put_line ('granting select on v_$pdbs to ' || dbrole );
		execute immediate 'grant select on v_$pdbs to ' || dbrole;

		--dbms_output.Put_line ('granting select on gv_$pdbs to ' || dbrole );
		execute immediate 'grant select on gv_$pdbs to ' || dbrole;

		--dbms_output.Put_line ('granting select on gv_$containers to ' || dbrole );
		execute immediate 'grant select on gv_$containers to ' || dbrole;

		--dbms_output.Put_line ('granting select on v_$containers to ' || dbrole );
		execute immediate 'grant select on v_$containers to ' || dbrole;

		--dbms_output.Put_line ('granting select on cdb_tablespaces to ' || dbrole );
		execute immediate 'grant select on cdb_tablespaces to ' || dbrole;

		--dbms_output.Put_line ('granting select on cdb_data_files to ' || dbrole );
		execute immediate 'grant select on cdb_data_files to ' || dbrole;

		--dbms_output.Put_line ('granting select on cdb_temp_files to ' || dbrole );
		execute immediate 'grant select on cdb_temp_files to ' || dbrole;

		--dbms_output.Put_line ('granting select on cdb_free_space to ' || dbrole );
		execute immediate 'grant select on cdb_free_space to ' || dbrole;

		--dbms_output.Put_line ('granting select on cdb_undo_extents to ' || dbrole );
		execute immediate 'grant select on cdb_undo_extents to ' || dbrole;

		--dbms_output.Put_line ('granting select on CDB_SCHEDULER_JOB_RUN_DETAILS to ' || dbrole );
		execute immediate 'grant select on CDB_SCHEDULER_JOB_RUN_DETAILS to ' || dbrole;

		--dbms_output.Put_line ('granting select on cdb_jobs to ' || dbrole );
		execute immediate 'grant select on cdb_jobs to ' || dbrole;

		--dbms_output.Put_line ('granting select on CDB_SCHEDULER_JOBS to ' || dbrole );
		execute immediate 'grant select on CDB_SCHEDULER_JOBS to ' || dbrole;

		--dbms_output.Put_line ('granting select on cdb_invalid_objects to ' || dbrole );
		execute immediate 'grant select on cdb_invalid_objects to ' || dbrole;

		--dbms_output.Put_line ('granting execute  on SYS.DBMS_DRS to ' || dbrole );
		execute immediate 'grant execute on SYS.DBMS_DRS to ' || dbrole;

		--dbms_output.Put_line ('granting select on v_$dg_broker_config to ' || dbrole );
		execute immediate 'grant select on v_$dg_broker_config to ' || dbrole;

		if (is_db_cdb = 'YES') then
			dbms_output.Put_line ('granting Oracle DB container DB privs to ' || dbrole);

			execute immediate 'alter user ' || monuser || ' set container_data=all CONTAINER=CURRENT';
		end if;

	end if;
	/* END OF  Privileges that can be added only for DBs above version 12 */


        /* Privileges that can be added only for DBs above version 12.2 */
	if (isdb_version_above_122) then
		dbms_output.Put_line ('granting Oracle DB 12.2+ privs to ' || dbrole);

		--dbms_output.Put_line ('granting read on v_$system_parameter to ' || dbrole );
		execute immediate 'grant read on v_$system_parameter to ' || dbrole;

		--dbms_output.Put_line ('granting read on gv_$system_parameter to ' || dbrole );
		execute immediate 'grant read on gv_$system_parameter to ' || dbrole;

		--dbms_output.Put_line ('granting read on v_$rsrcpdbmetric_history to ' || dbrole );
		execute immediate 'grant read on v_$rsrcpdbmetric_history to ' || dbrole;

		--dbms_output.Put_line ('granting read on gv_$rsrcpdbmetric_history to ' || dbrole );
		execute immediate 'grant read on gv_$rsrcpdbmetric_history to ' || dbrole;

		--dbms_output.Put_line ('granting read on v_$con_sysmetric_history to ' || dbrole );
		execute immediate 'grant read on v_$con_sysmetric_history to ' || dbrole;

		--dbms_output.Put_line ('granting gv_$con_sysmetric_history to ' || dbrole );
		execute immediate 'grant read on gv_$con_sysmetric_history to ' || dbrole;

	end if;
	/* END OF Privileges that can be added only for DBs above version 12.2 */

	select count(1)
	into ebs_tbl_cnt
	from dba_all_tables
	where table_name = upper('fnd_product_groups');

	if ( ebs_tbl_cnt > 0 ) then
		is_db_ebs := true;
		dbms_output.put_line('ebs tables detected.');
	else
		is_db_ebs := false;
		dbms_output.put_line('ebs not detected');
	end if;

    /* adding ebs privs */
	if (is_db_ebs) then
		dbms_output.put_line('granting EBS permissions.');
        --dbms_output.put_line('granting connect to ' || monuser);

		execute immediate 'grant connect to ' || monuser;
				--dbms_output.put_line('granting select on ebs tables to ' || monuser);

		execute immediate 'grant select on apps.fnd_oam_context_files to  ' || monuser;

		execute immediate 'grant select on apps.fnd_product_groups to  ' || monuser;

		execute immediate 'grant select on apps.fnd_conc_prog_onsite_info to  ' || monuser;

		execute immediate 'grant select on apps.fnd_concurrent_programs_vl to  ' || monuser;

		execute immediate 'grant select on apps.fnd_concurrent_requests to  ' || monuser;

		execute immediate 'grant select on apps.fnd_application_vl to  ' || monuser;

		execute immediate 'grant select on apps.fnd_concurrent_queues to  ' || monuser;

		execute immediate 'grant select on apps.fnd_lookups to  ' || monuser;

		execute immediate 'grant select on apps.fnd_concurrent_worker_requests to  ' || monuser;

		execute immediate 'grant select on apps.fnd_concurrent_worker_requests to  ' || monuser;

		execute immediate 'grant select on apps.fnd_concurrent_queues_vl to  ' || monuser;

		execute immediate 'grant select on apps.fnd_oam_fnduser_vl to  ' || monuser;

		execute immediate 'grant select on apps.fnd_form_sessions_v to  ' || monuser;

		execute immediate 'grant select on apps.fnd_cp_services to  ' || monuser;

		execute immediate 'grant select on apps.fnd_concurrent_processes to  ' || monuser;

		execute immediate 'grant select on apps.fnd_svc_components to  ' || monuser;

		execute immediate 'grant select on apps.fnd_log_messages to  ' || monuser;

		execute immediate 'grant select on apps.fnd_concurrent_programs to  ' || monuser;

		execute immediate 'grant select on apps.fnd_conflicts_domain to  ' || monuser;

		execute immediate 'grant select on apps.fnd_oracle_userid to  ' || monuser;

		execute immediate 'grant select on apps.fnd_app_servers to  ' || monuser;

		execute immediate 'grant select on apps.fnd_nodes to  ' || monuser;

		execute immediate 'grant select on apps.icx_sessions to  ' || monuser;

		execute immediate 'grant select on apps.fnd_user to  ' || monuser;

		execute immediate 'grant select on apps.fnd_responsibility to  ' || monuser;
        execute immediate 'grant select on apps.wf_deferred to  ' || monuser;
		execute immediate 'grant select on apps.wf_notification_in to  ' || monuser;
		execute immediate 'grant select on apps.wf_notification_out to  ' || monuser;


		/*dbms_output.put_line('granting execute on ebs packages to ' || monuser);*/

		execute immediate 'grant execute on apps.fnd_oam_em to ' || monuser;

		execute immediate 'grant execute on apps.fnd_profile to ' || monuser;

		execute immediate 'grant execute on apps.fnd_web_config to  ' || monuser;

		execute immediate 'grant execute on apps.fnd_web_sec to  ' || monuser;

		execute immediate 'grant execute on apps.iby_creditcard_pkg to  ' || monuser;

		execute immediate 'grant execute on apps.iby_security_pkg to  ' || monuser;

		execute immediate 'grant select on apps.iby_sys_security_options to  ' || monuser;

		execute immediate 'create or replace synonym  '
						|| monuser
						|| '.iby_sys_security_options for apps.iby_sys_security_options';

		execute immediate 'grant select on apps.fnd_user_preferences to  ' || monuser;

		execute immediate 'create or replace synonym  '
						|| monuser
						|| '.fnd_user_preferences for apps.fnd_user_preferences';

		execute immediate 'alter user '
						|| monuser
						|| ' enable editions';

		execute immediate 'create or replace synonym  '
						|| monuser
						|| '.fnd_web_config for apps.fnd_web_config';

		execute immediate 'create or replace synonym  '
						|| monuser
						|| '.iby_creditcard_pkg for apps.iby_creditcard_pkg';

		execute immediate 'create or replace synonym  '
						|| monuser
						|| '.iby_security_pkg for apps.iby_security_pkg';

		execute immediate 'create or replace synonym  '
						|| monuser
						|| '.fnd_web_sec for apps.fnd_web_sec';

		execute immediate 'grant select on apps.fnd_profile_options to  ' || monuser;

		execute immediate 'grant select on apps.fnd_profile_option_values to  ' || monuser;

		execute immediate 'grant select on apps.fnd_profile_options_tl to  ' || monuser;

		execute immediate 'grant select on apps.fnd_user to  ' || monuser;

		execute immediate 'grant select on apps.fnd_application to  ' || monuser;

		execute immediate 'grant select on apps.fnd_nodes to  ' || monuser;

		execute immediate 'grant select on apps.hr_operating_units to  ' || monuser;

		execute immediate 'create or replace synonym  '
						|| monuser
						|| '.fnd_profile_options for apps.fnd_profile_options';

		execute immediate 'create or replace synonym  '
						|| monuser
						|| '.fnd_profile_option_values for apps.fnd_profile_option_values';

		execute immediate 'create or replace synonym  '
						|| monuser
						|| '.fnd_profile_options_tl for apps.fnd_profile_options_tl';

		execute immediate 'create or replace synonym  '
						|| monuser
						|| '.fnd_user for apps.fnd_user';

		execute immediate 'create or replace synonym  '
						|| monuser
						|| '.fnd_application for apps.fnd_application';

		execute immediate 'create or replace synonym  '
						|| monuser
						|| '.fnd_responsibility for apps.fnd_responsibility';

		execute immediate 'create or replace synonym  '
						|| monuser
						|| '.fnd_nodes for apps.fnd_nodes';

		execute immediate 'create or replace synonym  '
						|| monuser
						|| '.hr_operating_units for apps.hr_operating_units';

	end if;

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


	execute immediate 'grant ' || dbrole || ' to ' || monuser;
	SELECT COUNT(*) into number_Of_grants_given
	FROM (SELECT DISTINCT table_name, PRIVILEGE
		  FROM dba_role_privs rp
		  JOIN role_tab_privs rtp
			ON (rp.granted_role = rtp.role)
		  WHERE rp.grantee = UPPER(monuser) );
	dbms_output.Put_line (number_Of_grants_given || ' Grants given to user ' || monuser);
end;
/
exit;

