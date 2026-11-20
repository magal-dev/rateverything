module Rateverything.DB.Connection
  ( newDbPool
  , withDb
  , firstRowOrFail
  ) where

import Data.ByteString (ByteString)
import Data.Pool (Pool, defaultPoolConfig, newPool, withResource)
import Database.PostgreSQL.Simple (Connection, close, connectPostgreSQL)

newDbPool :: ByteString -> IO (Pool Connection)
newDbPool databaseUrl =
  newPool (defaultPoolConfig (connectPostgreSQL databaseUrl) close idleConnectionTimeoutSeconds maxOpenConnections)

idleConnectionTimeoutSeconds :: Double
idleConnectionTimeoutSeconds = 60

maxOpenConnections :: Int
maxOpenConnections = 10

withDb :: Pool Connection -> (Connection -> IO a) -> IO a
withDb = withResource

firstRowOrFail :: String -> [row] -> IO row
firstRowOrFail _ (firstRow : _) = pure firstRow
firstRowOrFail expectedRowDescription [] =
  fail ("expected a " <> expectedRowDescription <> " but the query returned nothing")
