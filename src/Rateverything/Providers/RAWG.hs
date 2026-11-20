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

searchGames :: Manager -> Text -> Text -> IO (Either ProviderError [ExternalItem])
searchGames manager apiKey searchTerm =
  getJson
    manager
    "https://api.rawg.io/api/games"
    [("key", apiKey), ("search", searchTerm), ("page_size", "20")]
    []
    (withObject "RAWG search" $ \response -> response .: "results" >>= mapM parseGame)

parseGame :: Value -> Parser ExternalItem
parseGame = withObject "RAWG game" $ \game -> do
  rawgId <- game .: "id" :: Parser Int
  name <- game .: "name"
  releaseDate <- game .:? "released"
  backgroundImage <- game .:? "background_image"
  genreNames <- game .:? "genres" .!= [] >>= mapM (withObject "genre" (.: "name"))
  pure
    ExternalItem
      { source = "rawg"
      , externalId = T.pack (show rawgId)
      , title = name
      , subtitle = nonBlank (T.intercalate ", " genreNames)
      , year = releaseDate >>= yearFromDate
      , imageUrl = backgroundImage
      , description = Nothing
      }
