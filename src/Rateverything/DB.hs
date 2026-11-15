-- | PostgreSQL access. This module only re-exports the pieces under @DB/@, so
-- the rest of the app can @import qualified Rateverything.DB as DB@.
module Rateverything.DB
  ( -- * Connections and schema
    module Rateverything.DB.Connection
  , module Rateverything.DB.Migrations
    -- * Queries, one module per table
  , module Rateverything.DB.Users
  , module Rateverything.DB.Categories
  , module Rateverything.DB.Items
  , module Rateverything.DB.Reviews
  ) where

import Rateverything.DB.Categories
import Rateverything.DB.Connection (newDbPool, withDb)
import Rateverything.DB.Items hiding (itemColumns)
import Rateverything.DB.Migrations
import Rateverything.DB.Reviews
import Rateverything.DB.Users
