{-# LANGUAGE NoFieldSelectors #-}

-- | Domain types shared by the database layer, providers and the HTTP API.
module Rateverything.Types
  ( UserId
  , ItemId
  , CategoryId
  , ReviewId
  , User (..)
  , Category (..)
  , Item (..)
  , Review (..)
  , ExternalItem (..)
  , SearchHit (..)
  , ItemDetail (..)
  , DiaryEntry (..)
    -- * Requests
  , Credentials (..)
  , Session (..)
  , NewCategory (..)
  , NewReview (..)
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import Data.Time (Day, UTCTime)
import Database.SQLite.Simple (FromRow (..), field)
import GHC.Generics (Generic)

type UserId = Int
type ItemId = Int
type CategoryId = Int
type ReviewId = Int

data User = User
  { id :: UserId
  , username :: Text
  , avatarUrl :: Maybe Text
  , createdAt :: UTCTime
  }
  deriving stock (Show, Generic)
  deriving anyclass (ToJSON)

instance FromRow User where
  fromRow = User <$> field <*> field <*> field <*> field

-- | A kind of thing that can be rated. Built-in categories are backed by an
-- external provider ("tmdb-movie", "musicbrainz", ...); custom ones belong to
-- a user and hold manually created items.
data Category = Category
  { id :: CategoryId
  , slug :: Text
  , name :: Text
  , description :: Maybe Text
  , provider :: Maybe Text
  , ownerId :: Maybe UserId
  , createdAt :: UTCTime
  }
  deriving stock (Show, Generic)
  deriving anyclass (ToJSON)

instance FromRow Category where
  fromRow = Category <$> field <*> field <*> field <*> field <*> field <*> field <*> field

data Item = Item
  { id :: ItemId
  , categoryId :: CategoryId
  , title :: Text
  , subtitle :: Maybe Text
  , year :: Maybe Int
  , imageUrl :: Maybe Text
  , description :: Maybe Text
  , source :: Text
  , externalId :: Maybe Text
  , createdBy :: Maybe UserId
  , createdAt :: UTCTime
  }
  deriving stock (Show, Generic)
  deriving anyclass (ToJSON)

instance FromRow Item where
  fromRow =
    Item <$> field <*> field <*> field <*> field <*> field <*> field
      <*> field <*> field <*> field <*> field <*> field

-- | A diary entry: a rating and/or a written review of an item.
-- Ratings go from 1 to 10 (half stars on a 5-star scale).
data Review = Review
  { id :: ReviewId
  , userId :: UserId
  , username :: Text
  , avatarUrl :: Maybe Text
  , itemId :: ItemId
  , rating :: Maybe Int
  , body :: Maybe Text
  , liked :: Bool
  , consumedOn :: Maybe Day
  , createdAt :: UTCTime
  }
  deriving stock (Show, Generic)
  deriving anyclass (ToJSON)

instance FromRow Review where
  fromRow =
    Review <$> field <*> field <*> field <*> field <*> field
      <*> field <*> field <*> field <*> field <*> field

-- | What a provider returns from a search, before it is stored locally.
data ExternalItem = ExternalItem
  { source :: Text
  , externalId :: Text
  , title :: Text
  , subtitle :: Maybe Text
  , year :: Maybe Int
  , imageUrl :: Maybe Text
  , description :: Maybe Text
  }
  deriving stock (Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | A search result, with the local item id when it was already imported.
data SearchHit = SearchHit
  { item :: ExternalItem
  , itemId :: Maybe ItemId
  }
  deriving stock (Show, Generic)
  deriving anyclass (ToJSON)

data ItemDetail = ItemDetail
  { item :: Item
  , category :: Category
  , averageRating :: Maybe Double
  , ratingCount :: Int
  , reviews :: [Review]
  }
  deriving stock (Show, Generic)
  deriving anyclass (ToJSON)

data DiaryEntry = DiaryEntry
  { review :: Review
  , item :: Item
  }
  deriving stock (Show, Generic)
  deriving anyclass (ToJSON)

data Credentials = Credentials
  { username :: Text
  , password :: Text
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

data Session = Session
  { token :: Text
  , user :: User
  }
  deriving stock (Generic)
  deriving anyclass (ToJSON)

data NewCategory = NewCategory
  { name :: Text
  , description :: Maybe Text
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

data NewReview = NewReview
  { rating :: Maybe Int
  , body :: Maybe Text
  , liked :: Bool
  , consumedOn :: Maybe Day
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)
