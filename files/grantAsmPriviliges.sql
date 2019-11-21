SET ECHO ON

SET SERVEROUTPUT ON

SET VERIFY OFF

SET LINESIZE 32767

SET FEEDBACK OFF

SET HEADING OFF

DECLARE
    role_exist      INTEGER;
    monuser         VARCHAR2(25);
    user_exist      INTEGER;
    profile_exist   INTEGER;
    table_not_found EXCEPTION;
    PRAGMA exception_init ( table_not_found, -00942 );
BEGIN
    monuser := '&1';
    SELECT
        COUNT(*)
    INTO profile_exist
    FROM
        dba_profiles
    WHERE
        profile = upper('SERVICE_ACCOUNT');

    IF ( profile_exist = 0 ) THEN
        dbms_output.put_line('create profile service_account');
        EXECUTE IMMEDIATE 'create profile service_account limit composite_limit default sessions_per_user default cpu_per_session default cpu_per_call default logical_reads_per_session default logical_reads_per_call default	idle_time default connect_time default private_sga default failed_login_attempts unlimited password_life_time unlimited	password_reuse_time unlimited password_reuse_max unlimited password_verify_function null password_lock_time unlimited password_grace_time unlimited'
        ;
    ELSIF ( profile_exist > 0 ) THEN
        dbms_output.put_line('alter profile service_account');
        EXECUTE IMMEDIATE 'alter profile service_account limit composite_limit default sessions_per_user default cpu_per_session default cpu_per_call default logical_reads_per_session default logical_reads_per_call default	idle_time default connect_time default private_sga default failed_login_attempts unlimited password_life_time unlimited	password_reuse_time unlimited password_reuse_max unlimited password_verify_function null password_lock_time unlimited password_grace_time unlimited'
        ;
    END IF;

    SELECT
        COUNT(*)
    INTO user_exist
    FROM
        dba_users
    WHERE
        username = upper(monuser);

    IF ( user_exist = 0 ) THEN
        dbms_output.put_line('creating user ' || monuser);
        EXECUTE IMMEDIATE 'create user '
                          || monuser
                          || ' profile service_account identified by "&2"';
        EXECUTE IMMEDIATE 'grant sysasm to ' || monuser;
        dbms_output.put_line('OMC ASM User Created');
    ELSIF ( user_exist > 0 ) THEN
        dbms_output.put_line('altering account ' || monuser);
        EXECUTE IMMEDIATE 'alter user '
                          || monuser
                          || ' profile service_account account unlock identified by "&2"';
        EXECUTE IMMEDIATE 'grant sysasm to ' || monuser;
        dbms_output.put_line('OMC ASM User Updated');
    END IF;

END;
/

EXIT;
