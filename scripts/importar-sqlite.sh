#!/usr/bin/env bash
# Copia usuários, sessões, categorias, itens e reviews de um rateverything.db
# (versão SQLite) para o PostgreSQL em $DATABASE_URL, mantendo os ids.
#
#   ./scripts/importar-sqlite.sh rateverything.db
#
# Rode o app uma vez antes (para criar as tabelas). APAGA os dados que já
# estiverem no Postgres. As fotos não ficam no banco: copie a pasta uploads/.
set -euo pipefail

db="${1:-rateverything.db}"
: "${DATABASE_URL:?defina DATABASE_URL}"
[ -f "$db" ] || { echo "arquivo não encontrado: $db" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# NULL vira \N para o COPY distinguir de texto vazio.
export_table() {
  sqlite3 -csv -nullvalue '\N' "$db" "SELECT $2 FROM $1 ORDER BY 1" > "$tmp/$1.csv"
}
export_table users      "id, username, password_hash, avatar_url, created_at"
export_table sessions   "token_hash, user_id, created_at"
export_table categories "id, slug, name, description, provider, owner_id, created_at"
export_table items      "id, category_id, title, subtitle, year, image_url, description, source, external_id, created_by, created_at"
export_table reviews    "id, user_id, item_id, rating, body, liked, consumed_on, created_at"

copy() { echo "\\copy $1 ($2) FROM '$tmp/$1.csv' WITH (FORMAT csv, NULL '\\N')"; }

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q <<SQL
SET TIME ZONE 'UTC';  -- o SQLite grava CURRENT_TIMESTAMP em UTC
BEGIN;
TRUNCATE reviews, items, sessions, categories, users RESTART IDENTITY CASCADE;
$(copy users      "id, username, password_hash, avatar_url, created_at")
$(copy sessions   "token_hash, user_id, created_at")
$(copy categories "id, slug, name, description, provider, owner_id, created_at")
$(copy items      "id, category_id, title, subtitle, year, image_url, description, source, external_id, created_by, created_at")
$(copy reviews    "id, user_id, item_id, rating, body, liked, consumed_on, created_at")
-- Próximos ids continuam depois dos importados.
DO \$\$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['users', 'categories', 'items', 'reviews'] LOOP
    EXECUTE format('SELECT setval(pg_get_serial_sequence(%L, ''id''), COALESCE(MAX(id), 0) + 1, false) FROM %I', t, t);
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
