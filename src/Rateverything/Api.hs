{-# OPTIONS_GHC -Wno-orphans #-}

module Rateverything.Api
  ( Api
  , PublicApi
  , PrivateApi
  , NewItemForm (..)
  , AvatarForm (..)
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

type PrivateApi =
  AuthProtect "bearer"
    :> ( "me" :> Get '[JSON] User
          :<|> "me" :> "avatar" :> MultipartForm Tmp AvatarForm :> Post '[JSON] User
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
    year <- traverse parseYear (nonBlankInput "year")
    pure
      NewItemForm
        { title = title
        , subtitle = nonBlankInput "subtitle"
        , year = year
        , description = nonBlankInput "description"
        , imagePath = chosenImagePath
        }
    where
      nonBlankInput fieldName = case lookupInput fieldName form of
        Right value | not (T.null (T.strip value)) -> Just (T.strip value)
        _ -> Nothing
      parseYear yearText = maybe (Left "year must be a number") Right (readMaybe (T.unpack yearText))
      chosenImagePath = case lookupFile "image" form of
        Right file | not (T.null file.fdFileName) -> Just file.fdPayload
        _ -> Nothing

newtype AvatarForm = AvatarForm {imagePath :: FilePath}

instance FromMultipart Tmp AvatarForm where
  fromMultipart form = AvatarForm . fdPayload <$> lookupFile "image" form
