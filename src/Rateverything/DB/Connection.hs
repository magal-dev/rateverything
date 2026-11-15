-- | Connection pool and small helpers shared by the query modules.
module Rateverything.DB.Connection
  ( newDbPool
  , withDb
  , single
  ) where

import Data.ByteString (ByteString)
import Data.Pool (Pool, defaultPoolConfig, newPool, withResource)
import Database.PostgreSQL.Simple (Connection, close, connectPostgreSQL)

-- | Opening a PostgreSQL connection is expensive, so requests borrow one from a
-- pool (up to 10 connections, idle ones closed after 60 s).
newDbPool :: ByteString -> IO (Pool Connection)
newDbPool url = newPool (defaultPoolConfig (connectPostgreSQL url) close 60 10)

withDb :: Pool Connection -> (Connection -> IO a) -> IO a
withDb = withResource

-- | For queries that must return exactly the row just written or referenced.
single :: String -> [a] -> IO a
single _ (x : _) = pure x
single what [] = fail ("expected a " <> what <> " but the query returned nothing")
