module Rateverything.Handlers.Reviews
  ( addReview
  , deleteReview
  , getUserDiary
  ) where

import Control.Monad.IO.Class (liftIO)
import Data.Foldable (for_)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (Day, addDays, fromGregorian, getCurrentTime, utctDay)
import Rateverything.App
import qualified Rateverything.DB as DB
import Rateverything.Types
import Servant

addReview :: User -> ItemId -> NewReview -> AppM Review
addReview user itemId newReview = do
  for_ newReview.rating validateRating
  for_ newReview.consumedOn validateConsumedOn
  _ <- runDb (`DB.findItem` itemId) `orFailWith` (err404, "Item não encontrado")
  let cleanedReview =
        NewReview
          { rating = newReview.rating
          , body = nonBlankStripped =<< newReview.body
          , liked = newReview.liked
          , consumedOn = newReview.consumedOn
          }
  runDb $ \conn -> DB.insertReview conn user.id itemId cleanedReview

validateRating :: Int -> AppM ()
validateRating rating =
  failUnless (rating >= 1 && rating <= 10) err400 "A nota deve ir de 1 a 10 (meias estrelas)"

validateConsumedOn :: Day -> AppM ()
validateConsumedOn consumedOn = do
  latestAllowedDate <- liftIO tomorrowInUtc
  failUnless (consumedOn >= earliestAllowedDate && consumedOn <= latestAllowedDate) err400
    "A data precisa estar entre 1900 e hoje"

earliestAllowedDate :: Day
earliestAllowedDate = fromGregorian 1900 1 1

tomorrowInUtc :: IO Day
tomorrowInUtc = addDays 1 . utctDay <$> getCurrentTime

nonBlankStripped :: Text -> Maybe Text
nonBlankStripped text
  | T.null stripped = Nothing
  | otherwise = Just stripped
  where
    stripped = T.strip text

deleteReview :: User -> ReviewId -> AppM NoContent
deleteReview user reviewId = do
  wasDeleted <- runDb $ \conn -> DB.deleteOwnReview conn user.id reviewId
  failUnless wasDeleted err404 "Review não encontrada"
  pure NoContent

getUserDiary :: Text -> AppM [DiaryEntry]
getUserDiary username = runDb $ \conn -> DB.diaryOfUser conn username
