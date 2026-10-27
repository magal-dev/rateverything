-- | Albums (release groups) from MusicBrainz, with covers from the Cover Art Archive.
-- No API key is needed, but MusicBrainz requires a descriptive User-Agent and
-- allows about one request per second.
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

-- | Arguments: HTTP manager, User-Agent, search term.
searchAlbums :: Manager -> Text -> Text -> IO (Either ProviderError [ExternalItem])
searchAlbums manager userAgent term =
  getJson
    manager
    "https://musicbrainz.org/ws/2/release-group"
    [("query", term), ("fmt", "json"), ("limit", "20")]
    [("User-Agent", TE.encodeUtf8 userAgent), ("Accept", "application/json")]
    (withObject "MusicBrainz search" $ \o -> o .: "release-groups" >>= mapM parseReleaseGroup)

parseReleaseGroup :: Value -> Parser ExternalItem
parseReleaseGroup = withObject "release group" $ \o -> do
  mbid <- o .: "id"
  title <- o .: "title"
  firstRelease <- o .:? "first-release-date"
  primaryType <- o .:? "primary-type"
  credits <- o .:? "artist-credit" .!= [] >>= mapM parseCredit
  pure
    ExternalItem
      { source = "musicbrainz"
      , externalId = mbid
      , title = title
      , subtitle = nonBlank (T.concat credits)
      , year = firstRelease >>= yearFromDate
      , imageUrl = Just ("https://coverartarchive.org/release-group/" <> mbid <> "/front-250")
      , description = primaryType
      }
  where
    -- An artist credit is a list of names joined by phrases such as " feat. ".
    parseCredit = withObject "artist credit" $ \c -> do
      name <- c .: "name"
      joinPhrase <- c .:? "joinphrase"
      pure (name <> fromMaybe "" joinPhrase)
