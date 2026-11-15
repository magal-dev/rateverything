-- | Queries for users and their login sessions.
module Rateverything.DB.Users
  ( insertUser
  , findUserByName
  , findUserByTokenHash
  , setAvatar
  , insertSession
  , deleteSession
  ) where

import Control.Monad (void)
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Database.PostgreSQL.Simple
import Rateverything.DB.Connection (single)
import Rateverything.Types

userColumns :: Query
userColumns = "id, username, avatar_url, created_at"

insertUser :: Connection -> Text -> Text -> IO User
insertUser conn name passwordHash =
  single "row"
    =<< query conn ("INSERT INTO users (username, password_hash) VALUES (?, ?) RETURNING " <> userColumns) (name, passwordHash)

-- | Returns the user together with its password hash.
findUserByName :: Connection -> Text -> IO (Maybe (User, Text))
findUserByName conn name = do
  rows <- query conn ("SELECT " <> userColumns <> ", password_hash FROM users WHERE lower(username) = lower(?)") (Only name)
  pure $ case rows of
    (u :. Only h) : _ -> Just (u, h)
    [] -> Nothing

findUserByTokenHash :: Connection -> Text -> IO (Maybe User)
findUserByTokenHash conn tokenHash =
  listToMaybe
    <$> query
      conn
      "SELECT u.id, u.username, u.avatar_url, u.created_at FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?"
      (Only tokenHash)

-- | Sets the user's profile picture URL and returns the updated user.
setAvatar :: Connection -> UserId -> Text -> IO User
setAvatar conn uid url =
  single "row" =<< query conn ("UPDATE users SET avatar_url = ? WHERE id = ? RETURNING " <> userColumns) (url, uid)

insertSession :: Connection -> Text -> UserId -> IO ()
insertSession conn tokenHash uid =
  void $ execute conn "INSERT INTO sessions (token_hash, user_id) VALUES (?, ?)" (tokenHash, uid)

deleteSession :: Connection -> Text -> IO ()
deleteSession conn tokenHash = void $ execute conn "DELETE FROM sessions WHERE token_hash = ?" (Only tokenHash)
