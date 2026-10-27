-- | Runtime configuration, read from environment variables (and an optional @.env@ file).
module Rateverything.Config
  ( Config (..)
  , loadConfig
  ) where

import Control.Monad (forM_, when)
import Data.Char (isSpace)
import Data.Maybe (fromMaybe, isNothing)
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (doesFileExist)
import System.Environment (lookupEnv, setEnv)
import Text.Read (readMaybe)

data Config = Config
  { port :: Int
  , dbPath :: FilePath
  , uploadDir :: FilePath
  , staticDir :: FilePath
  , tmdbApiKey :: Maybe Text
  , tmdbLanguage :: Text
  , rawgApiKey :: Maybe Text
  , musicBrainzUserAgent :: Text
  }

loadConfig :: IO Config
loadConfig = do
  loadDotEnv ".env"
  port <- fromMaybe 8080 . (>>= readMaybe) <$> lookupEnv "PORT"
  dbPath <- envOr "DB_PATH" "rateverything.db"
  uploadDir <- envOr "UPLOAD_DIR" "uploads"
  staticDir <- envOr "STATIC_DIR" "static"
  tmdbApiKey <- optionalEnv "TMDB_API_KEY"
  tmdbLanguage <- T.pack <$> envOr "TMDB_LANGUAGE" "pt-BR"
  rawgApiKey <- optionalEnv "RAWG_API_KEY"
  musicBrainzUserAgent <- T.pack <$> envOr "MUSICBRAINZ_USER_AGENT" "Rateverything/0.1 ( https://github.com/ )"
  pure Config {..}
  where
    envOr name def = fromMaybe def <$> lookupEnv name
    optionalEnv name = do
      v <- lookupEnv name
      pure $ case T.strip . T.pack <$> v of
        Just t | not (T.null t) -> Just t
        _ -> Nothing

-- | Minimal @KEY=VALUE@ loader. Variables already set in the environment win.
loadDotEnv :: FilePath -> IO ()
loadDotEnv path = do
  exists <- doesFileExist path
  when exists $ do
    contents <- readFile path
    forM_ (lines contents) $ \line ->
      case break (== '=') (trim line) of
        (key@(c : _), '=' : value) | c /= '#' -> do
          current <- lookupEnv key
          when (isNothing current && not (null (trim value))) $ setEnv key (trim value)
        _ -> pure ()
  where
    trim = dropWhile isSpace . reverse . dropWhile isSpace . reverse
