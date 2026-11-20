module Main (main) where

import Control.Monad (forM_)
import Network.HTTP.Client.TLS (newTlsManager)
import Network.Wai.Handler.Warp (run)
import Network.Wai.Middleware.RequestLogger (logStdoutDev)
import Rateverything.App (Env (..))
import Rateverything.Config (Config (..), loadConfig)
import Rateverything.DB (applyPendingMigrations, newDbPool, withDb)
import Rateverything.Server (application)
import System.Directory (createDirectoryIfMissing)
import System.IO (BufferMode (LineBuffering), hSetBuffering, hSetEncoding, stdout, utf8)

main :: IO ()
main = do
  setUpUtf8LineBufferedOutput
  config <- loadConfig
  createDirectoryIfMissing True config.uploadDir
  pool <- newDbPool config.databaseUrl
  withDb pool applyPendingMigrations
  manager <- newTlsManager
  warnAboutMissingApiKeys config
  putStrLn ("Rateverything rodando em http://localhost:" <> show config.port)
  run config.port (logStdoutDev (application Env {config = config, manager = manager, pool = pool}))

setUpUtf8LineBufferedOutput :: IO ()
setUpUtf8LineBufferedOutput = do
  hSetBuffering stdout LineBuffering
  hSetEncoding stdout utf8

warnAboutMissingApiKeys :: Config -> IO ()
warnAboutMissingApiKeys config =
  forM_ missingKeyNames $ \keyName ->
    putStrLn ("Aviso: " <> keyName <> " não definida; a busca dessa categoria ficará indisponível.")
  where
    missingKeyNames =
      [keyName | (keyName, Nothing) <- [("TMDB_API_KEY", config.tmdbApiKey), ("RAWG_API_KEY", config.rawgApiKey)]]
