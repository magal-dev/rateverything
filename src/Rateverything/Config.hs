module Rateverything.Config
  ( Config (..)
  , loadConfig
  ) where

import Control.Monad (forM_, when)
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as BS8
import Data.Char (isSpace)
import Data.Maybe (fromMaybe, isNothing, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (doesFileExist)
import System.Environment (lookupEnv, setEnv)
import Text.Read (readMaybe)

data Config = Config
  { port :: Int
  , databaseUrl :: ByteString
  , uploadDir :: FilePath
  , staticDir :: FilePath
  , tmdbApiKey :: Maybe Text
  , tmdbLanguage :: Text
  , rawgApiKey :: Maybe Text
  , musicBrainzUserAgent :: Text
  }

loadConfig :: IO Config
loadConfig = do
  loadDotEnvFile ".env"
  port <- fromMaybe defaultPort . (>>= readMaybe) <$> lookupEnv "PORT"
  databaseUrl <- BS8.pack <$> envOrDefault "DATABASE_URL" defaultDatabaseUrl
  uploadDir <- envOrDefault "UPLOAD_DIR" "uploads"
  staticDir <- envOrDefault "STATIC_DIR" "static"
  tmdbApiKey <- nonBlankEnv "TMDB_API_KEY"
  tmdbLanguage <- T.pack <$> envOrDefault "TMDB_LANGUAGE" "pt-BR"
  rawgApiKey <- nonBlankEnv "RAWG_API_KEY"
  musicBrainzUserAgent <- T.pack <$> envOrDefault "MUSICBRAINZ_USER_AGENT" defaultMusicBrainzUserAgent
  pure Config {..}

defaultPort :: Int
defaultPort = 8080

defaultDatabaseUrl :: String
defaultDatabaseUrl = "postgresql://rateverything:rateverything@localhost:5432/rateverything"

defaultMusicBrainzUserAgent :: String
defaultMusicBrainzUserAgent = "Rateverything/0.1 ( https://github.com/ )"

envOrDefault :: String -> String -> IO String
envOrDefault variableName defaultValue = fromMaybe defaultValue <$> lookupEnv variableName

nonBlankEnv :: String -> IO (Maybe Text)
nonBlankEnv variableName = do
  value <- lookupEnv variableName
  pure $ case T.strip . T.pack <$> value of
    Just stripped | not (T.null stripped) -> Just stripped
    _ -> Nothing

loadDotEnvFile :: FilePath -> IO ()
loadDotEnvFile path = do
  fileExists <- doesFileExist path
  when fileExists $ do
    contents <- readFile path
    forM_ (mapMaybe parseDotEnvLine (lines contents)) $ \(variableName, value) ->
      setEnvUnlessAlreadySet variableName value

parseDotEnvLine :: String -> Maybe (String, String)
parseDotEnvLine line =
  case break (== '=') (trimSpaces line) of
    (variableName@(firstChar : _), '=' : value) | firstChar /= '#' -> Just (variableName, trimSpaces value)
    _ -> Nothing

setEnvUnlessAlreadySet :: String -> String -> IO ()
setEnvUnlessAlreadySet variableName value = do
  currentValue <- lookupEnv variableName
  when (isNothing currentValue && not (null value)) $
    setEnv variableName value

trimSpaces :: String -> String
trimSpaces = dropWhile isSpace . reverse . dropWhile isSpace . reverse
