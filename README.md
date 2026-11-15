# Rateverything

Um "Letterboxd para qualquer coisa": registre, dê nota (meias estrelas) e escreva reviews de filmes, séries, álbuns, jogos, livros — ou de qualquer categoria que você mesmo criar, com foto.

Backend em **Haskell** (Servant + Warp + SQLite), frontend estático em JS puro servido pelo próprio servidor.

## Rodando

Requisitos: GHC ≥ 9.6 e cabal (via [ghcup](https://www.haskell.org/ghcup/)).

```bash
cp .env.example .env     # preencha as chaves de API
cabal run rateverything
```

Abra http://localhost:8080.

### No GitHub Codespaces

O repositório tem um `.devcontainer/` com GHC 9.10.3 + cabal 3.16.1.0 (as mesmas versões do desenvolvimento local) e `sqlite3`.

1. No GitHub: **Code → Codespaces → Create codespace on master**. A tela pede `TMDB_API_KEY`, `RAWG_API_KEY` e `MUSICBRAINZ_USER_AGENT` — eles viram secrets do Codespaces e chegam ao app como variáveis de ambiente (não precisa de `.env`).
2. Na criação, o `postCreateCommand` roda `cabal update && cabal build` (a primeira vez demora ~10–15 min).
3. No terminal: `cabal run rateverything`. A porta 8080 é encaminhada e abre no navegador (`https://<codespace>-8080.app.github.dev`, privada por padrão).

O banco SQLite (`rateverything.db`) é criado e migrado sozinho no primeiro start. Para levar os dados locais (usuários, reviews, fotos), copie o banco e as imagens — eles não vão para o git:

```bash
gh codespace cp -e rateverything.db remote:/workspaces/rateverything/
gh codespace cp -e -r uploads remote:/workspaces/rateverything/
```

(ou arraste os arquivos para o Explorer do VS Code no Codespace, com o servidor parado). Os dados sobrevivem a parar/retomar o Codespace, mas somem se ele for **excluído** — o GitHub apaga Codespaces inativos após 30 dias, então baixe o `.db` de vez em quando como backup.

| Categoria | Provedor | Chave |
|-----------|----------|-------|
| Filmes, Séries | [TMDB](https://developer.themoviedb.org) | `TMDB_API_KEY` (v3, grátis) |
| Jogos | [RAWG](https://rawg.io/apidocs) | `RAWG_API_KEY` (grátis) |
| Álbuns | [MusicBrainz](https://musicbrainz.org/doc/MusicBrainz_API) + Cover Art Archive | nenhuma (só `MUSICBRAINZ_USER_AGENT` com contato) |
| Livros | [Open Library](https://openlibrary.org/developers/api) | nenhuma |

Sem chave, a busca daquela categoria responde 503 com a explicação; o resto funciona.

## Como funciona

- **Categorias**: as embutidas têm um `provider`; as criadas por usuários não têm e guardam itens manuais.
- **Busca**: consulta o provedor externo em tempo real (nada é salvo) + itens manuais da categoria. Cada resultado indica se já existe localmente (`itemId`).
- **Importação**: ao abrir um resultado externo, ele vira um `item` local (único por `source` + `external_id`), e aí pode receber reviews.
- **Itens manuais**: `multipart/form-data` com foto opcional. A imagem é validada pelos *magic bytes*, limitada a 5 MB e salva em `uploads/` com nome aleatório.
- **Reviews**: nota 1–10 (= ½ a 5 estrelas), texto, ♥ e data (de 1900 até hoje). Múltiplos registros por item (rever/reouvir) formam o diário.
- **Falhas de provedor**: se a API externa cai ou responde erro, a busca devolve 503 com uma mensagem amigável (o detalhe técnico vai só para o log, sem a chave de API) e o frontend oferece "tentar novamente".
- **Auth**: senha com bcrypt; sessão via token Bearer aleatório, só o hash SHA-256 fica no banco.

## Estrutura

```
app/Main.hs                         bootstrap: config, migrações, Warp
src/Rateverything/
  Api.hs                            tipo da API (Servant)
  Server.hs                         handlers e regras
  DB.hs                             SQLite: migrações e queries
  Types.hs                          tipos de domínio + JSON
  Auth.hs                           bcrypt, tokens, AuthHandler
  Uploads.hs                        armazenamento de imagens
  Config.hs                         variáveis de ambiente / .env
  Providers.hs                      roteia provider -> implementação
  Providers/{TMDB,RAWG,MusicBrainz,OpenLibrary}.hs
static/                             SPA (index.html, app.js, style.css)
```

Para adicionar um provedor novo: crie `Providers/X.hs` retornando `[ExternalItem]`, registre a chave em `Providers.hs` e insira a categoria numa nova migração em `DB.hs`.

## API

Público:

| Método | Rota | |
|---|---|---|
| POST | `/api/auth/register`, `/api/auth/login` | `{username, password}` → `{token, user}` |
| GET | `/api/categories` | |
| GET | `/api/categories/:slug/search?q=` | resultados externos + manuais |
| GET | `/api/categories/:slug/items` | itens locais recentes |
| GET | `/api/items/:id` | item, categoria, média, reviews |
| GET | `/api/users/:username/diary` | |

Com `Authorization: Bearer <token>`:

| Método | Rota | |
|---|---|---|
| GET | `/api/me` | |
| POST | `/api/me/avatar` | multipart: `image` (foto de perfil) → usuário atualizado |
| POST | `/api/auth/logout` | |
| POST | `/api/categories` | `{name, description}` |
| POST | `/api/categories/:slug/import` | um `ExternalItem` da busca |
| POST | `/api/categories/:slug/items` | multipart: `title`, `subtitle`, `year`, `description`, `image` |
| POST | `/api/items/:id/reviews` | `{rating, body, liked, consumedOn}` |
| DELETE | `/api/reviews/:id` | |

## Próximos passos

- Revalidar itens importados no provedor (hoje confia no payload da busca) e cachear buscas.
- Listas, watchlist ("quero ver/ouvir/jogar"), seguir usuários e feed de atividade.
- Campos customizados por categoria (ex.: uva/safra para vinhos) — `items` pode ganhar uma coluna JSON.
- Expiração de sessões, rate limiting e edição de reviews.
- PostgreSQL para produção (as queries são SQL padrão; trocar `sqlite-simple` por `postgresql-simple`/`hasql`).
- Testes (hspec + `servant-client` contra um banco temporário).
