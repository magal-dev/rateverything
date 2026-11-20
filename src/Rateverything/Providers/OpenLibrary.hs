module Rateverything.Providers.OpenLibrary
  ( searchBooks
  ) where

import Data.Aeson (Value, withObject, (.!=), (.:), (.:?))
import Data.Aeson.Types (Parser)
import Data.Text (Text)
import qualified Data.Text as T
import Network.HTTP.Client (Manager)
import Rateverything.Providers.Http
import Rateverything.Types (ExternalItem (..))

searchBooks :: Manager -> Text -> IO (Either ProviderError [ExternalItem])
searchBooks manager searchTerm =
  getJson
    manager
    "https://openlibrary.org/search.json"
    [("q", searchTerm), ("limit", "20"), ("fields", "key,title,author_name,first_publish_year,cover_i")]
    [("User-Agent", "Rateverything/0.1")]
    (withObject "Open Library search" $ \response -> response .: "docs" >>= mapM parseBook)

parseBook :: Value -> Parser ExternalItem
parseBook = withObject "Open Library doc" $ \book -> do
  workKey <- book .: "key"
  title <- book .: "title"
  authorNames <- book .:? "author_name" .!= []
  firstPublishYear <- book .:? "first_publish_year"
  coverId <- book .:? "cover_i" :: Parser (Maybe Int)
  pure
    ExternalItem
      { source = "openlibrary"
      , externalId = workKey
      , title = title
      , subtitle = nonBlank (T.intercalate ", " authorNames)
      , year = firstPublishYear
      , imageUrl = coverUrl <$> coverId
      , description = Nothing
      }

coverUrl :: Int -> Text
coverUrl coverId = "https://covers.openlibrary.org/b/id/" <> T.pack (show coverId) <> "-M.jpg"
