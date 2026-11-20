module Rateverything.App
  ( Env (..)
  , AppM
  , runDb
  , failWith
  , failUnless
  , orFailWith
  , saveUploadedImage
  ) where

import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ReaderT, asks)
import qualified Data.ByteString.Lazy as LBS
import Data.Pool (Pool)
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
import Database.PostgreSQL.Simple (Connection)
import Network.HTTP.Client (Manager)
import Rateverything.Config (Config (..))
import Rateverything.DB (withDb)
import Rateverything.Uploads (copyImageToUploads)
import Servant (Handler, ServerError (..), err400, throwError)

data Env = Env
  { config :: Config
  , manager :: Manager
  , pool :: Pool Connection
  }

type AppM = ReaderT Env Handler

runDb :: (Connection -> IO a) -> AppM a
runDb databaseAction = do
  pool <- asks (.pool)
  liftIO (withDb pool databaseAction)

failWith :: ServerError -> Text -> AppM a
failWith serverError message =
  throwError
    serverError
      { errBody = LBS.fromStrict (TE.encodeUtf8 message)
      , errHeaders = [("Content-Type", "text/plain; charset=utf-8")]
      }

failUnless :: Bool -> ServerError -> Text -> AppM ()
failUnless condition serverError message = unless condition (failWith serverError message)

orFailWith :: AppM (Maybe a) -> (ServerError, Text) -> AppM a
orFailWith lookupAction (serverError, message) =
  lookupAction >>= maybe (failWith serverError message) pure

saveUploadedImage :: FilePath -> AppM Text
saveUploadedImage temporaryPath = do
  uploadDir <- asks (.config.uploadDir)
  liftIO (copyImageToUploads uploadDir temporaryPath) >>= either (failWith err400) pure
