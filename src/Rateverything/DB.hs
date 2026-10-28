-- | SQLite access: connection handling, migrations and queries.
module Rateverything.DB
  ( withDb
  , migrate
    -- * Users and sessions
  , insertUser
  , findUserByName
  , findUserByTokenHash
  , setAvatar
  , insertSession
  , deleteSession
    -- * Categories
  , listCategories
  , findCategoryBySlug
  , findCategoryById
  , insertCategory
  , slugTaken
    -- * Items
  , findItem
  , listItemsInCategory
  , searchLocalItems
  , upsertExternalItem
  , insertManualItem
  , lookupImported
    -- * Reviews
  , insertReview
  , deleteReview
  , reviewsForItem
  , ratingStats
  , diaryFor
  ) where

import Control.Monad (forM_, unless)
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Database.SQLite.Simple
import Rateverything.Types

-- | SQLite connections are cheap, so each request opens its own. This avoids
-- sharing one connection (and its transactions) between Warp threads.
withDb :: FilePath -> (Connection -> IO a) -> IO a
withDb path action = withConnection path $ \conn -> do
  execute_ conn "PRAGMA foreign_keys = ON"
  execute_ conn "PRAGMA busy_timeout = 5000"
  action conn

-- | Applies every migration not yet recorded in @schema_migrations@.
migrate :: Connection -> IO ()
migrate conn = do
  execute_ conn "PRAGMA journal_mode = WAL"
  execute_ conn "CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY)"
  applied <- map fromOnly <$> query_ conn "SELECT version FROM schema_migrations"
  forM_ migrations $ \(version, statements) ->
    unless ((version :: Int) `elem` applied) $
      withTransaction conn $ do
        mapM_ (execute_ conn) statements
        execute conn "INSERT INTO schema_migrations (version) VALUES (?)" (Only version)

migrations :: [(Int, [Query])]
migrations =
  [ ( 1
    ,
      [ "CREATE TABLE users (\
        \  id INTEGER PRIMARY KEY,\
        \  username TEXT NOT NULL UNIQUE COLLATE NOCASE,\
        \  password_hash TEXT NOT NULL,\
        \  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP)"
      , "CREATE TABLE sessions (\
        \  token_hash TEXT PRIMARY KEY,\
        \  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,\
        \  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP)"
      , "CREATE TABLE categories (\
        \  id INTEGER PRIMARY KEY,\
        \  slug TEXT NOT NULL UNIQUE,\
        \  name TEXT NOT NULL,\
        \  description TEXT,\
        \  provider TEXT,\
        \  owner_id INTEGER REFERENCES users(id) ON DELETE CASCADE,\
        \  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP)"
      , "CREATE TABLE items (\
        \  id INTEGER PRIMARY KEY,\
        \  category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,\
        \  title TEXT NOT NULL,\
        \  subtitle TEXT,\
        \  year INTEGER,\
        \  image_url TEXT,\
        \  description TEXT,\
        \  source TEXT NOT NULL,\
        \  external_id TEXT,\
        \  created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,\
        \  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,\
        \  UNIQUE (source, external_id))"
      , "CREATE INDEX items_category ON items(category_id)"
      , "CREATE TABLE reviews (\
        \  id INTEGER PRIMARY KEY,\
        \  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,\
        \  item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,\
        \  rating INTEGER CHECK (rating BETWEEN 1 AND 10),\
        \  body TEXT,\
        \  liked INTEGER NOT NULL DEFAULT 0,\
        \  consumed_on DATE,\
        \  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP)"
      , "CREATE INDEX reviews_item ON reviews(item_id)"
      , "CREATE INDEX reviews_user ON reviews(user_id)"
      , "INSERT INTO categories (slug, name, description, provider) VALUES\
        \  ('filmes', 'Filmes', 'Filmes via TMDB', 'tmdb-movie'),\
        \  ('series', 'Séries', 'Séries via TMDB', 'tmdb-tv'),\
        \  ('albuns', 'Álbuns', 'Álbuns via MusicBrainz', 'musicbrainz'),\
        \  ('jogos', 'Jogos', 'Jogos via RAWG', 'rawg'),\
        \  ('livros', 'Livros', 'Livros via Open Library', 'openlibrary')"
      ]
    )
  , (2, ["ALTER TABLE users ADD COLUMN avatar_url TEXT"])
  , -- Users don't need to know which API backs a category; leaves edited descriptions alone.
    ( 3
    , [ "UPDATE categories SET description = 'do cinema ao streaming' WHERE slug = 'filmes' AND description = 'Filmes via TMDB'"
      , "UPDATE categories SET description = 'maratonas e temporadas' WHERE slug = 'series' AND description = 'Séries via TMDB'"
      , "UPDATE categories SET description = 'do lado A ao lado B' WHERE slug = 'albuns' AND description = 'Álbuns via MusicBrainz'"
      , "UPDATE categories SET description = 'do arcade ao mundo aberto' WHERE slug = 'jogos' AND description = 'Jogos via RAWG'"
      , "UPDATE categories SET description = 'da cabeceira à estante' WHERE slug = 'livros' AND description = 'Livros via Open Library'"
      ]
    )
  ]

-- Users and sessions ---------------------------------------------------------

userColumns :: Query
userColumns = "id, username, avatar_url, created_at"

insertUser :: Connection -> Text -> Text -> IO User
insertUser conn name passwordHash = do
  execute conn "INSERT INTO users (username, password_hash) VALUES (?, ?)" (name, passwordHash)
  uid <- fromIntegral <$> lastInsertRowId conn
  single "row" =<< query conn ("SELECT " <> userColumns <> " FROM users WHERE id = ?") (Only (uid :: Int))

-- | Returns the user together with its password hash.
findUserByName :: Connection -> Text -> IO (Maybe (User, Text))
findUserByName conn name = do
  rows <- query conn ("SELECT " <> userColumns <> ", password_hash FROM users WHERE username = ?") (Only name)
  pure $ case rows of
    (u :. Only h) : _ -> Just (u, h)
    [] -> Nothing

findUserByTokenHash :: Connection -> Text -> IO (Maybe User)
findUserByTokenHash conn tokenHash =
  listToMaybe
    <$> query
      conn
      "SELECT u.id, u.username, u.avatar_url, u.created_at FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?"
      (Only tokenHash)

-- | Sets the user's profile picture URL and returns the updated user.
setAvatar :: Connection -> UserId -> Text -> IO User
setAvatar conn uid url = do
  execute conn "UPDATE users SET avatar_url = ? WHERE id = ?" (url, uid)
  single "row" =<< query conn ("SELECT " <> userColumns <> " FROM users WHERE id = ?") (Only uid)

insertSession :: Connection -> Text -> UserId -> IO ()
insertSession conn tokenHash uid =
  execute conn "INSERT INTO sessions (token_hash, user_id) VALUES (?, ?)" (tokenHash, uid)

deleteSession :: Connection -> Text -> IO ()
deleteSession conn tokenHash = execute conn "DELETE FROM sessions WHERE token_hash = ?" (Only tokenHash)

-- Categories -----------------------------------------------------------------

categoryColumns :: Query
categoryColumns = "id, slug, name, description, provider, owner_id, created_at"

listCategories :: Connection -> IO [Category]
listCategories conn =
  query_ conn ("SELECT " <> categoryColumns <> " FROM categories ORDER BY owner_id IS NOT NULL, id")

findCategoryBySlug :: Connection -> Text -> IO (Maybe Category)
findCategoryBySlug conn slug =
  listToMaybe <$> query conn ("SELECT " <> categoryColumns <> " FROM categories WHERE slug = ?") (Only slug)

findCategoryById :: Connection -> CategoryId -> IO Category
findCategoryById conn cid =
  single "category" =<< query conn ("SELECT " <> categoryColumns <> " FROM categories WHERE id = ?") (Only cid)

slugTaken :: Connection -> Text -> IO Bool
slugTaken conn slug = do
  rows <- query conn "SELECT 1 FROM categories WHERE slug = ?" (Only slug) :: IO [Only Int]
  pure (not (null rows))

insertCategory :: Connection -> Text -> Text -> Maybe Text -> UserId -> IO Category
insertCategory conn slug name description owner = do
  execute
    conn
    "INSERT INTO categories (slug, name, description, owner_id) VALUES (?, ?, ?, ?)"
    (slug, name, description, owner)
  cid <- fromIntegral <$> lastInsertRowId conn
  single "row" =<< query conn ("SELECT " <> categoryColumns <> " FROM categories WHERE id = ?") (Only (cid :: Int))

-- Items ----------------------------------------------------------------------

itemColumns :: Query
itemColumns =
  "i.id, i.category_id, i.title, i.subtitle, i.year, i.image_url, i.description,\
  \ i.source, i.external_id, i.created_by, i.created_at"

findItem :: Connection -> ItemId -> IO (Maybe Item)
findItem conn iid =
  listToMaybe <$> query conn ("SELECT " <> itemColumns <> " FROM items i WHERE i.id = ?") (Only iid)

listItemsInCategory :: Connection -> CategoryId -> IO [Item]
listItemsInCategory conn cid =
  query
    conn
    ("SELECT " <> itemColumns <> " FROM items i WHERE i.category_id = ? ORDER BY i.created_at DESC LIMIT 100")
    (Only cid)

searchLocalItems :: Connection -> CategoryId -> Text -> IO [Item]
searchLocalItems conn cid term =
  query
    conn
    ( "SELECT " <> itemColumns <> " FROM items i\
      \ WHERE i.category_id = ? AND (i.title LIKE ? ESCAPE '\\' OR i.subtitle LIKE ? ESCAPE '\\')\
      \ ORDER BY i.title LIMIT 50"
    )
    (cid, pattern, pattern)
  where
    pattern = "%" <> escapeLike term <> "%"
    escapeLike = T.concatMap $ \c -> if c `elem` ['%', '_', '\\'] then T.pack ['\\', c] else T.singleton c

-- | Local ids of already-imported external items, keyed by external id.
lookupImported :: Connection -> Text -> [Text] -> IO [(Text, ItemId)]
lookupImported _ _ [] = pure []
lookupImported conn source externalIds =
  query
    conn
    ( "SELECT external_id, id FROM items WHERE source = ? AND external_id IN ("
        <> Query (T.intercalate "," (map (const "?") externalIds))
        <> ")"
    )
    (SQLText source : map SQLText externalIds)

-- | Stores an external item (or refreshes its metadata) and returns it.
upsertExternalItem :: Connection -> CategoryId -> ExternalItem -> IO Item
upsertExternalItem conn cid ext = do
  execute
    conn
    "INSERT INTO items (category_id, title, subtitle, year, image_url, description, source, external_id)\
    \ VALUES (?, ?, ?, ?, ?, ?, ?, ?)\
    \ ON CONFLICT (source, external_id) DO UPDATE SET\
    \   title = excluded.title, subtitle = excluded.subtitle, year = excluded.year,\
    \   image_url = excluded.image_url, description = excluded.description"
    ( (cid, ext.title, ext.subtitle, ext.year)
        :. (ext.imageUrl, ext.description, ext.source, ext.externalId)
    )
  single "row"
    =<< query
      conn
      ("SELECT " <> itemColumns <> " FROM items i WHERE i.source = ? AND i.external_id = ?")
      (ext.source, ext.externalId)

insertManualItem
  :: Connection -> CategoryId -> UserId -> Text -> Maybe Text -> Maybe Int -> Maybe Text -> Maybe Text -> IO Item
insertManualItem conn cid uid title subtitle year imageUrl description = do
  execute
    conn
    "INSERT INTO items (category_id, title, subtitle, year, image_url, description, source, created_by)\
    \ VALUES (?, ?, ?, ?, ?, ?, 'user', ?)"
    ((cid, title, subtitle, year) :. (imageUrl, description, uid))
  iid <- fromIntegral <$> lastInsertRowId conn
  single "row" =<< query conn ("SELECT " <> itemColumns <> " FROM items i WHERE i.id = ?") (Only (iid :: Int))

-- Reviews --------------------------------------------------------------------

reviewColumns :: Query
reviewColumns = "r.id, r.user_id, u.username, u.avatar_url, r.item_id, r.rating, r.body, r.liked, r.consumed_on, r.created_at"

insertReview :: Connection -> UserId -> ItemId -> NewReview -> IO Review
insertReview conn uid iid new = do
  execute
    conn
    "INSERT INTO reviews (user_id, item_id, rating, body, liked, consumed_on) VALUES (?, ?, ?, ?, ?, ?)"
    (uid, iid, new.rating, new.body, new.liked, new.consumedOn)
  rid <- fromIntegral <$> lastInsertRowId conn
  single "row"
    =<< query
      conn
      ("SELECT " <> reviewColumns <> " FROM reviews r JOIN users u ON u.id = r.user_id WHERE r.id = ?")
      (Only (rid :: Int))

-- | Deletes a review if it belongs to the given user. Returns whether a row was removed.
deleteReview :: Connection -> UserId -> ReviewId -> IO Bool
deleteReview conn uid rid = do
  execute conn "DELETE FROM reviews WHERE id = ? AND user_id = ?" (rid, uid)
  (> 0) <$> changes conn

reviewsForItem :: Connection -> ItemId -> IO [Review]
reviewsForItem conn iid =
  query
    conn
    ( "SELECT " <> reviewColumns <> " FROM reviews r JOIN users u ON u.id = r.user_id\
      \ WHERE r.item_id = ? ORDER BY r.created_at DESC LIMIT 100"
    )
    (Only iid)

-- | Average rating (1-10) and number of ratings for an item.
ratingStats :: Connection -> ItemId -> IO (Maybe Double, Int)
ratingStats conn iid = do
  rows <- query conn "SELECT AVG(rating), COUNT(rating) FROM reviews WHERE item_id = ?" (Only iid)
  pure $ case rows of
    (avg, n) : _ -> (avg, n)
    [] -> (Nothing, 0)

diaryFor :: Connection -> Text -> IO [DiaryEntry]
diaryFor conn name = do
  rows <-
    query
      conn
      ( "SELECT " <> reviewColumns <> ", " <> itemColumns <> " FROM reviews r\
        \ JOIN users u ON u.id = r.user_id JOIN items i ON i.id = r.item_id\
        \ WHERE u.username = ? ORDER BY COALESCE(r.consumed_on, r.created_at) DESC, r.id DESC LIMIT 200"
      )
      (Only name)
  pure [DiaryEntry {review = r, item = i} | r :. i <- rows]

-- | For queries that must return exactly the row just written or referenced.
single :: String -> [a] -> IO a
single _ (x : _) = pure x
single what [] = fail ("expected a " <> what <> " but the query returned nothing")
