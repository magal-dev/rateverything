-- | Password hashing and bearer-token sessions.
module Rateverything.Auth
  ( hashPassword
  , checkPassword
  , newSessionToken
  , hashToken
  , authHandler
  ) where

import Control.Monad.IO.Class (liftIO)
import Crypto.Hash (SHA256 (..), hashWith)
import qualified Crypto.KDF.BCrypt as BCrypt
import Crypto.Random (getRandomBytes)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base16 as Base16
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.Wai (Request, requestHeaders)
import Rateverything.DB (findUserByTokenHash, withDb)
import Rateverything.Types (User)
import Servant (err401, errBody, throwError)
import Servant.Server.Experimental.Auth (AuthHandler, mkAuthHandler)

hashPassword :: Text -> IO Text
hashPassword password = do
  h <- BCrypt.hashPassword 12 (TE.encodeUtf8 password) :: IO BS.ByteString
  pure (TE.decodeUtf8 h)

checkPassword :: Text -> Text -> Bool
checkPassword password stored = BCrypt.validatePassword (TE.encodeUtf8 password) (TE.encodeUtf8 stored)

-- | A random token handed to the client. Only its hash is stored.
newSessionToken :: IO Text
newSessionToken = do
  bytes <- getRandomBytes 32 :: IO BS.ByteString
  pure (TE.decodeUtf8 (Base16.encode bytes))

hashToken :: Text -> Text
hashToken = T.pack . show . hashWith SHA256 . TE.encodeUtf8

-- | Resolves @Authorization: Bearer <token>@ to the logged-in user.
authHandler :: FilePath -> AuthHandler Request User
authHandler dbPath = mkAuthHandler $ \req ->
  case lookup "Authorization" (requestHeaders req) >>= BS.stripPrefix "Bearer " of
    Nothing -> throwError err401 {errBody = "Missing bearer token"}
    Just token -> do
      user <- liftIO $ withDb dbPath $ \conn -> findUserByTokenHash conn (hashToken (TE.decodeLatin1 token))
      maybe (throwError err401 {errBody = "Invalid or expired session"}) pure user
