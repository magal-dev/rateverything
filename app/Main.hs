module Main (main) where

import Network.HTTP.Client.TLS (newTlsManager)
import Network.Wai.Handler.Warp (run)
import Network.Wai.Middleware.RequestLogger (logStdoutDev)
import Rateverything.App (Env (..))
import Rateverything.Config (Config (..), loadConfig)
import Rateverything.DB (migrate, newDbPool, withDb)
import Rateverything.Server (application)
import System.Directory (createDirectoryIfMissing)
import System.IO (BufferMode (LineBuffering), hSetBuffering, hSetEncoding, stdout, utf8)

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  hSetEncoding stdout utf8
  config <- loadConfig
  createDirectoryIfMissing True config.uploadDir
  pool <- newDbPool config.databaseUrl
  withDb pool migrate
  manager <- newTlsManager
  let missing = [name | (name, Nothing) <- [("TMDB_API_KEY", config.tmdbApiKey), ("RAWG_API_KEY", config.rawgApiKey)]]
  mapM_ (\name -> putStrLn ("Aviso: " <> name <> " não definida; a busca dessa categoria ficará indisponível.")) missing
  putStrLn ("Rateverything rodando em http://localhost:" <> show config.port)
  run config.port (logStdoutDev (application Env {config = config, manager = manager, pool = pool}))
