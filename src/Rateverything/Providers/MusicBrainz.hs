module Rateverything.Providers.MusicBrainz
  ( searchAlbums
  ) where

import Data.Aeson (Value, withObject, (.!=), (.:), (.:?))
import Data.Aeson.Types (Parser)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Client (Manager)
import Rateverything.Providers.Http
import Rateverything.Types (ExternalItem (..))

searchAlbums :: Manager -> Text -> Text -> IO (Either ProviderError [ExternalItem])
searchAlbums manager userAgent searchTerm =
  getJson
    manager
    "https://musicbrainz.org/ws/2/release-group"
    [("query", searchTerm), ("fmt", "json"), ("limit", "20")]
    [("User-Agent", TE.encodeUtf8 userAgent), ("Accept", "application/json")]
    (withObject "MusicBrainz search" $ \response -> response .: "release-groups" >>= mapM parseReleaseGroup)

parseReleaseGroup :: Value -> Parser ExternalItem
parseReleaseGroup = withObject "release group" $ \releaseGroup -> do
  musicBrainzId <- releaseGroup .: "id"
  title <- releaseGroup .: "title"
  firstReleaseDate <- releaseGroup .:? "first-release-date"
  primaryType <- releaseGroup .:? "primary-type"
  artistCreditParts <- releaseGroup .:? "artist-credit" .!= [] >>= mapM parseArtistCreditPart
  pure
    ExternalItem
      { source = "musicbrainz"
      , externalId = musicBrainzId
      , title = title
      , subtitle = nonBlank (T.concat artistCreditParts)
      , year = firstReleaseDate >>= yearFromDate
      , imageUrl = Just (coverArtUrl musicBrainzId)
      , description = primaryType
      }

parseArtistCreditPart :: Value -> Parser Text
parseArtistCreditPart = withObject "artist credit" $ \credit -> do
  artistName <- credit .: "name"
  joinPhrase <- credit .:? "joinphrase"
  pure (artistName <> fromMaybe "" joinPhrase)

coverArtUrl :: Text -> Text
coverArtUrl musicBrainzId = "https://coverartarchive.org/release-group/" <> musicBrainzId <> "/front-250"
