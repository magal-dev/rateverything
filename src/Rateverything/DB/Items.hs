-- | Queries for items: imported from providers or created by hand.
module Rateverything.DB.Items
  ( itemColumns
  , findItem
  , listItemsInCategory
  , searchLocalItems
  , upsertExternalItem
  , insertManualItem
  , lookupImported
  ) where

import Control.Monad (void)
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Database.PostgreSQL.Simple
import Rateverything.DB.Connection (single)
import Rateverything.Types

-- | Columns in 'Item' field order, for a query that aliases @items@ as @i@.
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

-- | Case-insensitive search (SQLite's LIKE ignored case; PostgreSQL needs ILIKE).
searchLocalItems :: Connection -> CategoryId -> Text -> IO [Item]
searchLocalItems conn cid term =
  query
    conn
    ( "SELECT " <> itemColumns <> " FROM items i\
      \ WHERE i.category_id = ? AND (i.title ILIKE ? ESCAPE '\\' OR i.subtitle ILIKE ? ESCAPE '\\')\
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
  query conn "SELECT external_id, id FROM items WHERE source = ? AND external_id IN ?" (source, In externalIds)

-- | Stores an external item (or refreshes its metadata) and returns it.
upsertExternalItem :: Connection -> CategoryId -> ExternalItem -> IO Item
upsertExternalItem conn cid ext = do
  void $
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
  Only iid <-
    single "row"
      =<< query
        conn
        "INSERT INTO items (category_id, title, subtitle, year, image_url, description, source, created_by)\
        \ VALUES (?, ?, ?, ?, ?, ?, 'user', ?) RETURNING id"
        ((cid, title, subtitle, year) :. (imageUrl, description, uid))
  single "row" =<< query conn ("SELECT " <> itemColumns <> " FROM items i WHERE i.id = ?") (Only (iid :: ItemId))
