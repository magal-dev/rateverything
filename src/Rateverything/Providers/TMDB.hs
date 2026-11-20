module Rateverything.Providers.TMDB
  ( searchMovies
  , searchSeries
  ) where

import Data.Aeson (Value, withObject, (.:), (.:?))
import qualified Data.Aeson.Key as Key
import Data.Aeson.Types (Parser)
import Data.Text (Text)
import qualified Data.Text as T
import Network.HTTP.Client (Manager)
import Rateverything.Providers.Http
import Rateverything.Types (ExternalItem (..))

data TmdbCatalog = TmdbCatalog
  { searchPath :: String
  , sourceKey :: Text
  , titleField :: Text
  , releaseDateField :: Text
  }

movieCatalog :: TmdbCatalog
movieCatalog =
  TmdbCatalog {searchPath = "movie", sourceKey = "tmdb-movie", titleField = "title", releaseDateField = "release_date"}

seriesCatalog :: TmdbCatalog
seriesCatalog =
  TmdbCatalog {searchPath = "tv", sourceKey = "tmdb-tv", titleField = "name", releaseDateField = "first_air_date"}

searchMovies :: Manager -> Text -> Text -> Text -> IO (Either ProviderError [ExternalItem])
searchMovies = searchCatalog movieCatalog

searchSeries :: Manager -> Text -> Text -> Text -> IO (Either ProviderError [ExternalItem])
searchSeries = searchCatalog seriesCatalog

searchCatalog :: TmdbCatalog -> Manager -> Text -> Text -> Text -> IO (Either ProviderError [ExternalItem])
searchCatalog catalog manager apiKey language searchTerm =
  getJson
    manager
    ("https://api.themoviedb.org/3/search/" <> catalog.searchPath)
    [("api_key", apiKey), ("language", language), ("query", searchTerm), ("include_adult", "false")]
    []
    (withObject "TMDB search" $ \response -> response .: "results" >>= mapM (parseResult catalog))

parseResult :: TmdbCatalog -> Value -> Parser ExternalItem
parseResult catalog = withObject "TMDB result" $ \result -> do
  tmdbId <- result .: "id" :: Parser Int
  title <- result .: Key.fromText catalog.titleField
  originalTitle <- result .:? Key.fromText ("original_" <> catalog.titleField)
  releaseDate <- result .:? Key.fromText catalog.releaseDateField
  posterPath <- result .:? "poster_path"
  overview <- result .:? "overview"
  pure
    ExternalItem
      { source = catalog.sourceKey
      , externalId = T.pack (show tmdbId)
      , title = title
      , subtitle = if originalTitle == Just title then Nothing else originalTitle
      , year = releaseDate >>= yearFromDate
      , imageUrl = posterUrl <$> posterPath
      , description = nonBlank =<< overview
      }

posterUrl :: Text -> Text
posterUrl posterPath = "https://image.tmdb.org/t/p/w342" <> posterPath
