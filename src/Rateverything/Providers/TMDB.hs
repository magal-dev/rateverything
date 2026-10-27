-- | Films and TV series from The Movie Database (https://developer.themoviedb.org).
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

-- | Arguments: HTTP manager, API key (v3), language (e.g. @pt-BR@), search term.
searchMovies :: Manager -> Text -> Text -> Text -> IO (Either ProviderError [ExternalItem])
searchMovies = search "movie" "tmdb-movie" "title" "release_date"

searchSeries :: Manager -> Text -> Text -> Text -> IO (Either ProviderError [ExternalItem])
searchSeries = search "tv" "tmdb-tv" "name" "first_air_date"

search :: String -> Text -> Text -> Text -> Manager -> Text -> Text -> Text -> IO (Either ProviderError [ExternalItem])
search kind source titleKey dateKey manager apiKey language term =
  getJson
    manager
    ("https://api.themoviedb.org/3/search/" <> kind)
    [("api_key", apiKey), ("language", language), ("query", term), ("include_adult", "false")]
    []
    (withObject "TMDB search" $ \o -> o .: "results" >>= mapM parseResult)
  where
    parseResult :: Value -> Parser ExternalItem
    parseResult = withObject "TMDB result" $ \o -> do
      tmdbId <- o .: "id" :: Parser Int
      title <- o .: Key.fromText titleKey
      original <- o .:? Key.fromText ("original_" <> titleKey)
      date <- o .:? Key.fromText dateKey
      poster <- o .:? "poster_path"
      overview <- o .:? "overview"
      pure
        ExternalItem
          { source = source
          , externalId = T.pack (show tmdbId)
          , title = title
          , subtitle = if original == Just title then Nothing else original
          , year = date >>= yearFromDate
          , imageUrl = ("https://image.tmdb.org/t/p/w342" <>) <$> poster
          , description = nonBlank =<< overview
          }
