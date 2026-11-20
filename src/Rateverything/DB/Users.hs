module Rateverything.DB.Users
  ( insertUser
  , findUserWithPasswordHash
  , findUserBySessionTokenHash
  , setAvatarUrl
  , insertSession
  , deleteSession
  ) where

import Control.Monad (void)
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Database.PostgreSQL.Simple
import Rateverything.DB.Connection (firstRowOrFail)
import Rateverything.Types

userColumns :: Query
userColumns = "id, username, avatar_url, created_at"

insertUser :: Connection -> Text -> Text -> IO User
insertUser conn username passwordHash =
  firstRowOrFail "row"
    =<< query
      conn
      ("INSERT INTO users (username, password_hash) VALUES (?, ?) RETURNING " <> userColumns)
      (username, passwordHash)

findUserWithPasswordHash :: Connection -> Text -> IO (Maybe (User, Text))
findUserWithPasswordHash conn username = do
  rows <-
    query
      conn
      ("SELECT " <> userColumns <> ", password_hash FROM users WHERE lower(username) = lower(?)")
      (Only username)
  pure $ case rows of
    (user :. Only passwordHash) : _ -> Just (user, passwordHash)
    [] -> Nothing

findUserBySessionTokenHash :: Connection -> Text -> IO (Maybe User)
findUserBySessionTokenHash conn tokenHash =
  listToMaybe
    <$> query
      conn
      "SELECT u.id, u.username, u.avatar_url, u.created_at\
      \ FROM sessions s JOIN users u ON u.id = s.user_id\
      \ WHERE s.token_hash = ?"
      (Only tokenHash)

setAvatarUrl :: Connection -> UserId -> Text -> IO User
setAvatarUrl conn userId avatarUrl =
  firstRowOrFail "row"
    =<< query conn ("UPDATE users SET avatar_url = ? WHERE id = ? RETURNING " <> userColumns) (avatarUrl, userId)

insertSession :: Connection -> Text -> UserId -> IO ()
insertSession conn tokenHash userId =
  void $ execute conn "INSERT INTO sessions (token_hash, user_id) VALUES (?, ?)" (tokenHash, userId)

deleteSession :: Connection -> Text -> IO ()
deleteSession conn tokenHash =
  void $ execute conn "DELETE FROM sessions WHERE token_hash = ?" (Only tokenHash)
