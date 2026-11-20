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
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Client
import Network.HTTP.Types (RequestHeaders, statusCode)
import Text.Read (readMaybe)

data ProviderError
  = ProviderUnavailable Text
  | ProviderNotConfigured Text
  deriving stock (Show)

type HttpResult = Either HttpException (Response LBS.ByteString)

getJson
  :: Manager
  -> String
  -> [(Text, Text)]
  -> RequestHeaders
  -> (Value -> Parser a)
  -> IO (Either ProviderError a)
getJson manager url queryParameters extraHeaders parseBody = do
  request <- buildRequest url queryParameters extraHeaders
  result <- sendRetryingOnceIfRateLimited manager request
  pure (interpretResult parseBody result)

buildRequest :: String -> [(Text, Text)] -> RequestHeaders -> IO Request
buildRequest url queryParameters extraHeaders = do
  baseRequest <- parseRequest url
  pure $
    setQueryString encodedParameters $
      baseRequest {requestHeaders = extraHeaders <> requestHeaders baseRequest}
  where
    encodedParameters = [(TE.encodeUtf8 name, Just (TE.encodeUtf8 value)) | (name, value) <- queryParameters]

sendRetryingOnceIfRateLimited :: Manager -> Request -> IO HttpResult
sendRetryingOnceIfRateLimited manager request = do
  firstAttempt <- send
  case firstAttempt of
    Right response | isRateLimited response -> do
      threadDelay retryDelayMicroseconds
      send
    _ -> pure firstAttempt
  where
    send = try @HttpException (httpLbs request manager)

isRateLimited :: Response body -> Bool
isRateLimited response = statusCodeOf response `elem` [429, 503]

retryDelayMicroseconds :: Int
retryDelayMicroseconds = 1_100_000

statusCodeOf :: Response body -> Int
statusCodeOf = statusCode . responseStatus

interpretResult :: (Value -> Parser a) -> HttpResult -> Either ProviderError a
interpretResult parseBody result = case result of
  Left (HttpExceptionRequest _ failureContent) ->
    unavailable ("HTTP error: " <> T.pack (show failureContent))
  Left (InvalidUrlException _ reason) ->
    unavailable ("Invalid URL: " <> T.pack reason)
  Right response
    | statusCodeOf response /= 200 ->
        unavailable ("Provider answered HTTP " <> T.pack (show (statusCodeOf response)))
    | otherwise -> case eitherDecode (responseBody response) >>= parseEither parseBody of
        Left parseError -> unavailable ("Unexpected provider response: " <> T.pack parseError)
        Right parsed -> Right parsed
  where
    unavailable = Left . ProviderUnavailable

yearFromDate :: Text -> Maybe Int
yearFromDate = readMaybe . T.unpack . T.take 4

nonBlank :: Text -> Maybe Text
nonBlank text = if T.null (T.strip text) then Nothing else Just text
