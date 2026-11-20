module Rateverything.DB.Categories
  ( listCategories
  , findCategoryBySlug
  , findCategoryById
  , insertCategory
  , isSlugTaken
  ) where

import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Database.PostgreSQL.Simple
import Rateverything.DB.Connection (firstRowOrFail)
import Rateverything.Types

categoryColumns :: Query
categoryColumns = "id, slug, name, description, provider, owner_id, created_at"

selectCategories :: Query
selectCategories = "SELECT " <> categoryColumns <> " FROM categories"

listCategories :: Connection -> IO [Category]
listCategories conn =
  query_ conn (selectCategories <> " ORDER BY owner_id IS NOT NULL, id")

findCategoryBySlug :: Connection -> Text -> IO (Maybe Category)
findCategoryBySlug conn slug =
  listToMaybe <$> query conn (selectCategories <> " WHERE slug = ?") (Only slug)

findCategoryById :: Connection -> CategoryId -> IO Category
findCategoryById conn categoryId =
  firstRowOrFail "category" =<< query conn (selectCategories <> " WHERE id = ?") (Only categoryId)

isSlugTaken :: Connection -> Text -> IO Bool
isSlugTaken conn slug = do
  matchingRows <- query conn "SELECT 1 FROM categories WHERE slug = ?" (Only slug) :: IO [Only Int]
  pure (not (null matchingRows))

insertCategory :: Connection -> Text -> Text -> Maybe Text -> UserId -> IO Category
insertCategory conn slug name description ownerId =
  firstRowOrFail "row"
    =<< query
      conn
      ("INSERT INTO categories (slug, name, description, owner_id) VALUES (?, ?, ?, ?) RETURNING " <> categoryColumns)
      (slug, name, description, ownerId)
