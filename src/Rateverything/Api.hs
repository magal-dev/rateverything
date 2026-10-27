{-# OPTIONS_GHC -Wno-orphans #-}

-- | The HTTP API, described as a Servant type.
module Rateverything.Api
  ( Api
  , PublicApi
  , PrivateApi
  , NewItemForm (..)
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Rateverything.Types
import Servant
import Servant.Multipart
import Servant.Server.Experimental.Auth (AuthServerData)
import Text.Read (readMaybe)

type instance AuthServerData (AuthProtect "bearer") = User

type PublicApi =
  "auth" :> "register" :> ReqBody '[JSON] Credentials :> Post '[JSON] Session
    :<|> "auth" :> "login" :> ReqBody '[JSON] Credentials :> Post '[JSON] Session
    :<|> "categories" :> Get '[JSON] [Category]
    :<|> "categories" :> Capture "slug" Text :> "search" :> QueryParam' '[Required, Strict] "q" Text :> Get '[JSON] [SearchHit]
    :<|> "categories" :> Capture "slug" Text :> "items" :> Get '[JSON] [Item]
    :<|> "items" :> Capture "itemId" ItemId :> Get '[JSON] ItemDetail
    :<|> "users" :> Capture "username" Text :> "diary" :> Get '[JSON] [DiaryEntry]

-- | Endpoints that need @Authorization: Bearer <token>@.
type PrivateApi =
  AuthProtect "bearer"
    :> ( "me" :> Get '[JSON] User
          :<|> "auth" :> "logout" :> Header' '[Required, Strict] "Authorization" Text :> PostNoContent
          :<|> "categories" :> ReqBody '[JSON] NewCategory :> Post '[JSON] Category
          :<|> "categories" :> Capture "slug" Text :> "import" :> ReqBody '[JSON] ExternalItem :> Post '[JSON] Item
          :<|> "categories" :> Capture "slug" Text :> "items" :> MultipartForm Tmp NewItemForm :> Post '[JSON] Item
          :<|> "items" :> Capture "itemId" ItemId :> "reviews" :> ReqBody '[JSON] NewReview :> Post '[JSON] Review
          :<|> "reviews" :> Capture "reviewId" ReviewId :> DeleteNoContent
       )

type Api =
  "api" :> (PublicApi :<|> PrivateApi)
    :<|> "uploads" :> Raw
    :<|> Raw

-- | A manually created item, sent as @multipart/form-data@ so it can carry a cover image.
data NewItemForm = NewItemForm
  { title :: Text
  , subtitle :: Maybe Text
  , year :: Maybe Int
  , description :: Maybe Text
  , imagePath :: Maybe FilePath
  }

instance FromMultipart Tmp NewItemForm where
  fromMultipart form = do
    title <- lookupInput "title" form
    year <- traverse parseYear (optionalInput "year")
    pure
      NewItemForm
        { title = title
        , subtitle = optionalInput "subtitle"
        , year = year
        , description = optionalInput "description"
        , imagePath = case lookupFile "image" form of
            Right file | not (T.null file.fdFileName) -> Just file.fdPayload
            _ -> Nothing
        }
    where
      optionalInput name = case lookupInput name form of
        Right v | not (T.null (T.strip v)) -> Just (T.strip v)
        _ -> Nothing
      parseYear v = maybe (Left "year must be a number") Right (readMaybe (T.unpack v))
