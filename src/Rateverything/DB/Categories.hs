-- | Queries for categories (built-in and user-created).
module Rateverything.DB.Categories
  ( listCategories
  , findCategoryBySlug
  , findCategoryById
  , insertCategory
  , slugTaken
  ) where

import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Database.PostgreSQL.Simple
import Rateverything.DB.Connection (single)
import Rateverything.Types

categoryColumns :: Query
categoryColumns = "id, slug, name, description, provider, owner_id, created_at"

-- | Built-in categories first, then user-created ones, oldest first.
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
insertCategory conn slug name description owner =
  single "row"
    =<< query
      conn
      ("INSERT INTO categories (slug, name, description, owner_id) VALUES (?, ?, ?, ?) RETURNING " <> categoryColumns)
      (slug, name, description, owner)
