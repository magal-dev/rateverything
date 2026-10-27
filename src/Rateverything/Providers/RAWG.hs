-- | Video games from RAWG (https://rawg.io/apidocs).
module Rateverything.Providers.RAWG
  ( searchGames
  ) where

import Data.Aeson (Value, withObject, (.!=), (.:), (.:?))
import Data.Aeson.Types (Parser)
import Data.Text (Text)
import qualified Data.Text as T
import Network.HTTP.Client (Manager)
import Rateverything.Providers.Http
import Rateverything.Types (ExternalItem (..))

-- | Arguments: HTTP manager, API key, search term.
searchGames :: Manager -> Text -> Text -> IO (Either ProviderError [ExternalItem])
searchGames manager apiKey term =
  getJson
    manager
    "https://api.rawg.io/api/games"
    [("key", apiKey), ("search", term), ("page_size", "20")]
    []
    (withObject "RAWG search" $ \o -> o .: "results" >>= mapM parseGame)

parseGame :: Value -> Parser ExternalItem
parseGame = withObject "RAWG game" $ \o -> do
  rawgId <- o .: "id" :: Parser Int
  name <- o .: "name"
  released <- o .:? "released"
  image <- o .:? "background_image"
  genres <- o .:? "genres" .!= [] >>= mapM (withObject "genre" (.: "name"))
  pure
    ExternalItem
      { source = "rawg"
      , externalId = T.pack (show rawgId)
      , title = name
      , subtitle = nonBlank (T.intercalate ", " genres)
      , year = released >>= yearFromDate
      , imageUrl = image
      , description = Nothing
      }
