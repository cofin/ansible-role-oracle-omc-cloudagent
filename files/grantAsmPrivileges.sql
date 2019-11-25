SET ECHO OFF

SET SERVEROUTPUT OFF

SET VERIFY OFF

SET LINESIZE 32767

SET FEEDBACK OFF

SET HEADING OFF

DECLARE
    monuser         VARCHAR2(25);
    user_exist      INTEGER;
    profile_exist   INTEGER;
    table_not_found EXCEPTION;
    PRAGMA exception_init ( table_not_found, -00942 );
BEGIN
    monuser := '&1';
    dbms_output.put_line('creating user ' || monuser);
    EXECUTE IMMEDIATE 'create user '
                      || monuser
                      || ' identified by "&2"';
    EXECUTE IMMEDIATE 'grant sysasm to ' || monuser;
    dbms_output.put_line('OMC ASM User Created');
END;
/

EXIT;
