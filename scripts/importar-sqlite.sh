#!/usr/bin/env bash
set -euo pipefail

sqlite_db="${1:-rateverything.db}"
: "${DATABASE_URL:?defina DATABASE_URL}"
[ -f "$sqlite_db" ] || { echo "arquivo não encontrado: $sqlite_db" >&2; exit 1; }

csv_dir="$(mktemp -d)"
trap 'rm -rf "$csv_dir"' EXIT

tables_in_dependency_order=(users sessions categories items reviews)
declare -A columns_of=(
  [users]="id, username, password_hash, avatar_url, created_at"
  [sessions]="token_hash, user_id, created_at"
  [categories]="id, slug, name, description, provider, owner_id, created_at"
  [items]="id, category_id, title, subtitle, year, image_url, description, source, external_id, created_by, created_at"
  [reviews]="id, user_id, item_id, rating, body, liked, consumed_on, created_at"
)

export_sqlite_table_to_csv() {
  local table="$1"
  sqlite3 -csv -nullvalue '\N' "$sqlite_db" "SELECT ${columns_of[$table]} FROM $table ORDER BY 1" > "$csv_dir/$table.csv"
}

psql_copy_commands() {
  local table
  for table in "${tables_in_dependency_order[@]}"; do
    echo "\\copy $table (${columns_of[$table]}) FROM '$csv_dir/$table.csv' WITH (FORMAT csv, NULL '\\N')"
  done
}

for table in "${tables_in_dependency_order[@]}"; do
  export_sqlite_table_to_csv "$table"
done

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q <<SQL
SET TIME ZONE 'UTC';
BEGIN;
TRUNCATE reviews, items, sessions, categories, users RESTART IDENTITY CASCADE;
$(psql_copy_commands)
DO \$\$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['users', 'categories', 'items', 'reviews'] LOOP
    EXECUTE format(
      'SELECT setval(pg_get_serial_sequence(%L, ''id''), COALESCE(MAX(id), 0) + 1, false) FROM %I',
      table_name, table_name);
  END LOOP;
END
\$\$;
COMMIT;
SQL

psql "$DATABASE_URL" -c "SELECT
  (SELECT count(*) FROM users) AS usuarios,
  (SELECT count(*) FROM categories) AS categorias,
  (SELECT count(*) FROM items) AS itens,
  (SELECT count(*) FROM reviews) AS reviews"
