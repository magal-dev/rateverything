module Rateverything.Providers
  ( searchProvider
  ) where

import Data.Text (Text)
import Network.HTTP.Client (Manager)
import Rateverything.Config (Config (..))
import Rateverything.Providers.Http (ProviderError (..))
import Rateverything.Providers.MusicBrainz (searchAlbums)
import Rateverything.Providers.OpenLibrary (searchBooks)
import Rateverything.Providers.RAWG (searchGames)
import Rateverything.Providers.TMDB (searchMovies, searchSeries)
import Rateverything.Types (ExternalItem)

type SearchResult = IO (Either ProviderError [ExternalItem])

searchProvider :: Config -> Manager -> Text -> Text -> SearchResult
searchProvider config manager providerKey searchTerm = case providerKey of
  "tmdb-movie" ->
    withApiKey "TMDB_API_KEY" config.tmdbApiKey $ \apiKey ->
      searchMovies manager apiKey config.tmdbLanguage searchTerm
  "tmdb-tv" ->
    withApiKey "TMDB_API_KEY" config.tmdbApiKey $ \apiKey ->
      searchSeries manager apiKey config.tmdbLanguage searchTerm
  "rawg" ->
    withApiKey "RAWG_API_KEY" config.rawgApiKey $ \apiKey ->
      searchGames manager apiKey searchTerm
  "musicbrainz" -> searchAlbums manager config.musicBrainzUserAgent searchTerm
  "openlibrary" -> searchBooks manager searchTerm
  unknownKey -> pure (Left (ProviderUnavailable ("Unknown provider: " <> unknownKey)))

withApiKey :: Text -> Maybe Text -> (Text -> SearchResult) -> SearchResult
withApiKey variableName maybeApiKey searchWithKey =
  maybe (pure (Left (ProviderNotConfigured variableName))) searchWithKey maybeApiKey
