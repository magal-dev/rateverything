-- | Books from Open Library (https://openlibrary.org/developers/api). No API key needed.
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
searchBooks manager term =
  getJson
    manager
    "https://openlibrary.org/search.json"
    [("q", term), ("limit", "20"), ("fields", "key,title,author_name,first_publish_year,cover_i")]
    [("User-Agent", "Rateverything/0.1")]
    (withObject "Open Library search" $ \o -> o .: "docs" >>= mapM parseDoc)

parseDoc :: Value -> Parser ExternalItem
parseDoc = withObject "Open Library doc" $ \o -> do
  key <- o .: "key"
  title <- o .: "title"
  authors <- o .:? "author_name" .!= []
  firstYear <- o .:? "first_publish_year"
  cover <- o .:? "cover_i" :: Parser (Maybe Int)
  pure
    ExternalItem
      { source = "openlibrary"
      , externalId = key
      , title = title
      , subtitle = nonBlank (T.intercalate ", " authors)
      , year = firstYear
      , imageUrl = (\c -> "https://covers.openlibrary.org/b/id/" <> T.pack (show c) <> "-M.jpg") <$> cover
      , description = Nothing
      }
