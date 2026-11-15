-- | Sign-up, login, logout and the profile picture.
module Rateverything.Handlers.Auth
  ( register
  , login
  , logout
  , updateAvatar
  ) where

import Control.Exception (tryJust)
import Control.Monad (unless, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (asks)
import Data.Char (isAsciiLower, isDigit)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Database.PostgreSQL.Simple as SQL
import Rateverything.Api (AvatarForm (..))
import Rateverything.App
import Rateverything.Auth (checkPassword, hashPassword, hashToken, newSessionToken)
import Rateverything.Config (Config (..))
import qualified Rateverything.DB as DB
import Rateverything.Types
import Rateverything.Uploads (saveImage)
import Servant

register :: Credentials -> AppM Session
register creds = do
  let name = T.strip creds.username
  unless (validUsername name) $
    failWith err400 "Nome de usuário deve ter 3 a 30 caracteres: letras minúsculas, números ou _"
  when (T.length creds.password < 8) $
    failWith err400 "A senha precisa ter pelo menos 8 caracteres"
  hashed <- liftIO (hashPassword creds.password)
  result <- runDb $ \conn -> tryJust uniqueViolation (DB.insertUser conn name hashed)
  case result of
    Left () -> failWith err409 "Esse nome de usuário já existe"
    Right user -> startSession user
  where
    -- 23505 = unique_violation (the lower(username) index); other errors propagate.
    uniqueViolation e = if SQL.sqlState e == "23505" then Just () else Nothing
    validUsername n =
      T.length n >= 3 && T.length n <= 30 && T.all (\c -> isAsciiLower c || isDigit c || c == '_') n

login :: Credentials -> AppM Session
login creds = do
  found <- runDb $ \conn -> DB.findUserByName conn (T.strip creds.username)
  case found of
    Just (user, stored) | checkPassword creds.password stored -> startSession user
    _ -> failWith err401 "Usuário ou senha inválidos"

startSession :: User -> AppM Session
startSession user = do
  token <- liftIO newSessionToken
  runDb $ \conn -> DB.insertSession conn (hashToken token) user.id
  pure Session {token = token, user = user}

logout :: Text -> AppM NoContent
logout header = do
  let token = T.strip (T.drop (T.length "Bearer ") header)
  runDb $ \conn -> DB.deleteSession conn (hashToken token)
  pure NoContent

updateAvatar :: User -> AvatarForm -> AppM User
updateAvatar user form = do
  uploadDir <- asks (.config.uploadDir)
  url <- liftIO (saveImage uploadDir form.imagePath) >>= either (failWith err400) pure
  runDb $ \conn -> DB.setAvatar conn user.id url
