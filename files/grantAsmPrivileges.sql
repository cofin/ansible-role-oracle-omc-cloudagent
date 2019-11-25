SET ECHO OFF

SET SERVEROUTPUT ON

SET VERIFY OFF

SET LINESIZE 32767

SET FEEDBACK OFF

SET HEADING OFF

DECLARE
    monuser         VARCHAR2(25);
    profile_exist   INTEGER;
    user_exists exception;
    table_not_found EXCEPTION;
    PRAGMA exception_init ( user_exists, -01920 );
BEGIN
    monuser := '&1';
    begin
        dbms_output.put_line('creating user ' || monuser);
        EXECUTE IMMEDIATE 'create user '
                        || monuser
                        || ' identified by "&2"';
    exception when user_exists then
        dbms_output.put_line('user already exists.  altering ' || monuser);

        EXECUTE IMMEDIATE 'alter user '
                  || monuser
                  || ' identified by "&2"';

    end;
    EXECUTE IMMEDIATE 'grant sysasm to ' || monuser;
    dbms_output.put_line('OMC ASM User Deployed');
END;
/

EXIT;
