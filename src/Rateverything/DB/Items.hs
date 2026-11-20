module Rateverything.DB.Items
  ( itemColumns
  , findItem
  , listRecentItemsInCategory
  , searchItemsInCategory
  , upsertExternalItem
  , insertManualItem
  , findImportedItemIds
  ) where

import Control.Monad (void)
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Database.PostgreSQL.Simple
import Rateverything.DB.Connection (firstRowOrFail)
import Rateverything.Types

itemColumns :: Query
itemColumns =
  "i.id, i.category_id, i.title, i.subtitle, i.year, i.image_url, i.description,\
  \ i.source, i.external_id, i.created_by, i.created_at"

selectItems :: Query
selectItems = "SELECT " <> itemColumns <> " FROM items i"

selectItemById :: Query
selectItemById = selectItems <> " WHERE i.id = ?"

findItem :: Connection -> ItemId -> IO (Maybe Item)
findItem conn itemId =
  listToMaybe <$> query conn selectItemById (Only itemId)

listRecentItemsInCategory :: Connection -> CategoryId -> IO [Item]
listRecentItemsInCategory conn categoryId =
  query
    conn
    (selectItems <> " WHERE i.category_id = ? ORDER BY i.created_at DESC LIMIT 100")
    (Only categoryId)

searchItemsInCategory :: Connection -> CategoryId -> Text -> IO [Item]
searchItemsInCategory conn categoryId searchTerm =
  query
    conn
    ( selectItems
        <> " WHERE i.category_id = ?\
           \ AND (i.title ILIKE ? ESCAPE '\\' OR i.subtitle ILIKE ? ESCAPE '\\')\
           \ ORDER BY i.title LIMIT 50"
    )
    (categoryId, containsPattern, containsPattern)
  where
    containsPattern = "%" <> escapeLikeWildcards searchTerm <> "%"

escapeLikeWildcards :: Text -> Text
escapeLikeWildcards = T.concatMap escapeCharacter
  where
    escapeCharacter character
      | character `elem` ['%', '_', '\\'] = T.pack ['\\', character]
      | otherwise = T.singleton character

findImportedItemIds :: Connection -> Text -> [Text] -> IO [(Text, ItemId)]
findImportedItemIds _ _ [] = pure []
findImportedItemIds conn source externalIds =
  query conn "SELECT external_id, id FROM items WHERE source = ? AND external_id IN ?" (source, In externalIds)

upsertExternalItem :: Connection -> CategoryId -> ExternalItem -> IO Item
upsertExternalItem conn categoryId externalItem = do
  void $
    execute
      conn
      "INSERT INTO items (category_id, title, subtitle, year, image_url, description, source, external_id)\
      \ VALUES (?, ?, ?, ?, ?, ?, ?, ?)\
      \ ON CONFLICT (source, external_id) DO UPDATE SET\
      \   title = excluded.title, subtitle = excluded.subtitle, year = excluded.year,\
      \   image_url = excluded.image_url, description = excluded.description"
      ( (categoryId, externalItem.title, externalItem.subtitle, externalItem.year)
          :. (externalItem.imageUrl, externalItem.description, externalItem.source, externalItem.externalId)
      )
  firstRowOrFail "row"
    =<< query
      conn
      (selectItems <> " WHERE i.source = ? AND i.external_id = ?")
      (externalItem.source, externalItem.externalId)

insertManualItem :: Connection -> NewManualItem -> IO Item
insertManualItem conn newItem = do
  Only insertedItemId <-
    firstRowOrFail "row"
      =<< query
        conn
        "INSERT INTO items (category_id, title, subtitle, year, image_url, description, source, created_by)\
        \ VALUES (?, ?, ?, ?, ?, ?, 'user', ?) RETURNING id"
        ( (newItem.categoryId, newItem.title, newItem.subtitle, newItem.year)
            :. (newItem.imageUrl, newItem.description, newItem.createdBy)
        )
  firstRowOrFail "row" =<< query conn selectItemById (Only (insertedItemId :: ItemId))
