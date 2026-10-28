-- | Small helpers shared by the external catalogue providers.
module Rateverything.Providers.Http
  ( ProviderError (..)
  , getJson
  , yearFromDate
  , nonBlank
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (try)
import Data.Aeson (Value, eitherDecode)
import Data.Aeson.Types (Parser, parseEither)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Client
import Network.HTTP.Types (RequestHeaders, statusCode)
import Text.Read (readMaybe)

-- | Why a provider search failed. The detail is for the server log only: it
-- may be technical, and is never shown to users.
data ProviderError
  = -- | The provider could not be reached or answered with an error.
    ProviderUnavailable Text
  | -- | The server lacks the API key (named here) the provider needs.
    ProviderNotConfigured Text
  deriving stock (Show)

-- | GETs a URL with query parameters and runs a JSON parser over the response body.
getJson
  :: Manager
  -> String
  -> [(Text, Text)]
  -> RequestHeaders
  -> (Value -> Parser a)
  -> IO (Either ProviderError a)
getJson manager url params headers parser = do
  base <- parseRequest url
  let request =
        setQueryString [(TE.encodeUtf8 k, Just (TE.encodeUtf8 v)) | (k, v) <- params] $
          base {requestHeaders = headers <> requestHeaders base}
  first <- try @HttpException (httpLbs request manager)
  -- Rate-limited providers (MusicBrainz allows ~1 req/s) answer 429/503: retry once.
  result <- case first of
    Right response | statusCode (responseStatus response) `elem` [429, 503] -> do
      threadDelay 1_100_000
      try (httpLbs request manager)
    _ -> pure first
  pure $ case result of
    -- Only the exception's content: the request itself carries the API key.
    Left (HttpExceptionRequest _ content) -> Left (ProviderUnavailable ("HTTP error: " <> T.pack (show content)))
    Left (InvalidUrlException _ reason) -> Left (ProviderUnavailable ("Invalid URL: " <> T.pack reason))
    Right response
      | statusCode (responseStatus response) /= 200 ->
          Left (ProviderUnavailable ("Provider answered HTTP " <> T.pack (show (statusCode (responseStatus response)))))
      | otherwise -> case eitherDecode (responseBody response) >>= parseEither parser of
          Left err -> Left (ProviderUnavailable ("Unexpected provider response: " <> T.pack err))
          Right a -> Right a

-- | Extracts the year from dates like @2019@, @2019-05@ or @2019-05-30@.
yearFromDate :: Text -> Maybe Int
yearFromDate = readMaybe . T.unpack . T.take 4

nonBlank :: Text -> Maybe Text
nonBlank t = if T.null (T.strip t) then Nothing else Just t
