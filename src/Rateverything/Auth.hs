module Rateverything.Auth
  ( hashPassword
  , passwordMatchesHash
  , generateSessionToken
  , hashSessionToken
  , sessionTokenFromAuthorizationHeader
  , bearerAuthHandler
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
import Data.Pool (Pool)
import Database.PostgreSQL.Simple (Connection)
import Network.Wai (Request, requestHeaders)
import Rateverything.DB (findUserBySessionTokenHash, withDb)
import Rateverything.Types (User)
import Servant (Handler, err401, errBody, throwError)
import Servant.Server.Experimental.Auth (AuthHandler, mkAuthHandler)

bcryptCost :: Int
bcryptCost = 12

sessionTokenByteCount :: Int
sessionTokenByteCount = 32

hashPassword :: Text -> IO Text
hashPassword password = do
  passwordHash <- BCrypt.hashPassword bcryptCost (TE.encodeUtf8 password) :: IO BS.ByteString
  pure (TE.decodeUtf8 passwordHash)

passwordMatchesHash :: Text -> Text -> Bool
passwordMatchesHash password storedHash =
  BCrypt.validatePassword (TE.encodeUtf8 password) (TE.encodeUtf8 storedHash)

generateSessionToken :: IO Text
generateSessionToken = do
  randomBytes <- getRandomBytes sessionTokenByteCount :: IO BS.ByteString
  pure (TE.decodeUtf8 (Base16.encode randomBytes))

hashSessionToken :: Text -> Text
hashSessionToken = T.pack . show . hashWith SHA256 . TE.encodeUtf8

bearerPrefix :: Text
bearerPrefix = "Bearer "

sessionTokenFromAuthorizationHeader :: Text -> Text
sessionTokenFromAuthorizationHeader header = T.strip (T.drop (T.length bearerPrefix) header)

bearerAuthHandler :: Pool Connection -> AuthHandler Request User
bearerAuthHandler pool = mkAuthHandler $ \request ->
  case bearerTokenOf request of
    Nothing -> throwError err401 {errBody = "Missing bearer token"}
    Just token -> findLoggedInUser pool token

bearerTokenOf :: Request -> Maybe BS.ByteString
bearerTokenOf request =
  lookup "Authorization" (requestHeaders request) >>= BS.stripPrefix (TE.encodeUtf8 bearerPrefix)

findLoggedInUser :: Pool Connection -> BS.ByteString -> Handler User
findLoggedInUser pool token = do
  let tokenHash = hashSessionToken (TE.decodeLatin1 token)
  maybeUser <- liftIO $ withDb pool $ \conn -> findUserBySessionTokenHash conn tokenHash
  maybe (throwError err401 {errBody = "Invalid or expired session"}) pure maybeUser
