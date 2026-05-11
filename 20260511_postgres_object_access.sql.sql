
WITH
table_grants AS (
  SELECT DISTINCT
    tp.table_schema    AS schema_name,
    tp.table_name      AS object_name,
    'TABLE'            AS object_type,
    tp.privilege_type,
    tp.grantee::text   AS grantee_name
  FROM information_schema.table_privileges tp
  WHERE tp.table_schema NOT IN ('pg_catalog', 'information_schema')
),
roles AS (
  SELECT r.oid, r.rolname, r.rolcanlogin
  FROM pg_roles r
),
-- 1) Grant recorded directly on a login-capable role (treat as "user" in reporting)
direct_user AS (
  SELECT
    g.schema_name,
    g.object_name,
    g.object_type,
    'Direct'::text AS given_via,
    NULL::text     AS role_name,
    r.rolname      AS user_name,
    g.privilege_type
  FROM table_grants g
  JOIN roles r ON r.rolname = g.grantee_name AND r.rolcanlogin
),
-- 2) Grant to a non-login role: show the role row as "Direct" to that role
direct_role AS (
  SELECT
    g.schema_name,
    g.object_name,
    g.object_type,
    'Direct'::text AS given_via,
    r.rolname      AS role_name,
    NULL::text     AS user_name,
    g.privilege_type
  FROM table_grants g
  JOIN roles r ON r.rolname = g.grantee_name AND NOT r.rolcanlogin
),
-- 3) Members of that role inherit privileges (one level of membership)
via_role AS (
  SELECT
    g.schema_name,
    g.object_name,
    g.object_type,
    'Via Role'::text AS given_via,
    parent.rolname   AS role_name,
    m.rolname        AS user_name,
    g.privilege_type
  FROM table_grants g
  JOIN roles parent ON parent.rolname = g.grantee_name AND NOT parent.rolcanlogin
  JOIN pg_auth_members am ON am.roleid = parent.oid
  JOIN roles m ON m.oid = am.member AND m.rolcanlogin
)
--insert into edw.postgres_object_access
select
    system,
  schema_name   AS schema,
  object_name   AS object_name,
  given_via     AS given_via_role_direct,
  role_name     AS role_name,
  user_name     AS user_name,
  privilege_type
FROM (
  SELECT 'Prod' as system, * FROM direct_user
  UNION ALL
  SELECT 'Prod' as system, * FROM direct_role
  UNION ALL
  SELECT 'Prod' as system, * FROM via_role)