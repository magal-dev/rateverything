-- | The handler monad and the environment shared by every request.
module Rateverything.App
  ( Env (..)
  , AppM
  , runDb
  , failWith
  ) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ReaderT, asks)
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
import Data.Pool (Pool)
import Database.PostgreSQL.Simple (Connection)
import Network.HTTP.Client (Manager)
import Rateverything.Config (Config (..))
import Rateverything.DB (withDb)
import Servant (Handler, ServerError (..), throwError)

data Env = Env
  { config :: Config
  , manager :: Manager
  , pool :: Pool Connection
  }

type AppM = ReaderT Env Handler

runDb :: (Connection -> IO a) -> AppM a
runDb action = do
  pool <- asks (.pool)
  liftIO (withDb pool action)

-- | Aborts the request with the given status and a plain-text message.
failWith :: ServerError -> Text -> AppM a
failWith err message =
  throwError err {errBody = LBS.fromStrict (TE.encodeUtf8 message), errHeaders = [("Content-Type", "text/plain; charset=utf-8")]}
