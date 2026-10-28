-- | Dispatches a category's @provider@ key to the matching external catalogue.
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

-- | Searches the provider registered under the given key.
searchProvider :: Config -> Manager -> Text -> Text -> IO (Either ProviderError [ExternalItem])
searchProvider config manager provider term = case provider of
  "tmdb-movie" -> withKey "TMDB_API_KEY" config.tmdbApiKey $ \k -> searchMovies manager k config.tmdbLanguage term
  "tmdb-tv" -> withKey "TMDB_API_KEY" config.tmdbApiKey $ \k -> searchSeries manager k config.tmdbLanguage term
  "rawg" -> withKey "RAWG_API_KEY" config.rawgApiKey $ \k -> searchGames manager k term
  "musicbrainz" -> searchAlbums manager config.musicBrainzUserAgent term
  "openlibrary" -> searchBooks manager term
  other -> pure (Left (ProviderUnavailable ("Unknown provider: " <> other)))
  where
    withKey name key action = maybe (pure (Left (ProviderNotConfigured name))) action key
