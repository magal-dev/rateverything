module Rateverything.Handlers.Auth
  ( register
  , login
  , logout
  , updateAvatar
  ) where

import Control.Exception (tryJust)
import Control.Monad.IO.Class (liftIO)
import Data.Char (isAsciiLower, isDigit)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Database.PostgreSQL.Simple as SQL
import Rateverything.Api (AvatarForm (..))
import Rateverything.App
import Rateverything.Auth
  ( generateSessionToken
  , hashPassword
  , hashSessionToken
  , passwordMatchesHash
  , sessionTokenFromAuthorizationHeader
  )
import qualified Rateverything.DB as DB
import Rateverything.Types
import Servant

register :: Credentials -> AppM Session
register credentials = do
  let username = T.strip credentials.username
  failUnless (isValidUsername username) err400
    "Nome de usuário deve ter 3 a 30 caracteres: letras minúsculas, números ou _"
  failUnless (T.length credentials.password >= minimumPasswordLength) err400
    "A senha precisa ter pelo menos 8 caracteres"
  passwordHash <- liftIO (hashPassword credentials.password)
  insertResult <- runDb $ \conn ->
    tryJust onUniqueViolation (DB.insertUser conn username passwordHash)
  case insertResult of
    Left () -> failWith err409 "Esse nome de usuário já existe"
    Right user -> startSessionFor user

minimumPasswordLength :: Int
minimumPasswordLength = 8

isValidUsername :: Text -> Bool
isValidUsername username =
  T.length username >= 3 && T.length username <= 30 && T.all isAllowedUsernameCharacter username
  where
    isAllowedUsernameCharacter character = isAsciiLower character || isDigit character || character == '_'

onUniqueViolation :: SQL.SqlError -> Maybe ()
onUniqueViolation sqlError
  | SQL.sqlState sqlError == uniqueViolationState = Just ()
  | otherwise = Nothing
  where
    uniqueViolationState = "23505"

login :: Credentials -> AppM Session
login credentials = do
  maybeUser <- runDb $ \conn -> DB.findUserWithPasswordHash conn (T.strip credentials.username)
  case maybeUser of
    Just (user, storedHash) | passwordMatchesHash credentials.password storedHash -> startSessionFor user
    _ -> failWith err401 "Usuário ou senha inválidos"

startSessionFor :: User -> AppM Session
startSessionFor user = do
  token <- liftIO generateSessionToken
  runDb $ \conn -> DB.insertSession conn (hashSessionToken token) user.id
  pure Session {token = token, user = user}

logout :: Text -> AppM NoContent
logout authorizationHeader = do
  let token = sessionTokenFromAuthorizationHeader authorizationHeader
  runDb $ \conn -> DB.deleteSession conn (hashSessionToken token)
  pure NoContent

updateAvatar :: User -> AvatarForm -> AppM User
updateAvatar user form = do
  avatarUrl <- saveUploadedImage form.imagePath
  runDb $ \conn -> DB.setAvatarUrl conn user.id avatarUrl
