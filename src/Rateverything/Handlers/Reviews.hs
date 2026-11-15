-- | Writing and deleting reviews, and the user's diary.
module Rateverything.Handlers.Reviews
  ( addReview
  , removeReview
  , diary
  ) where

import Control.Monad (unless, when)
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
addReview user iid new = do
  case new.rating of
    Just r | r < 1 || r > 10 -> failWith err400 "A nota deve ir de 1 a 10 (meias estrelas)"
    _ -> pure ()
  for_ new.consumedOn $ \day -> do
    -- One day of slack for users in time zones ahead of UTC.
    tomorrow <- liftIO (addDays 1 . utctDay <$> getCurrentTime)
    when (day < earliestDiaryDate || day > tomorrow) $
      failWith err400 "A data precisa estar entre 1900 e hoje"
  _ <- runDb (`DB.findItem` iid) >>= maybe (failWith err404 "Item não encontrado") pure
  let body = new.body >>= \b -> if T.null (T.strip b) then Nothing else Just (T.strip b)
  runDb $ \conn -> DB.insertReview conn user.id iid NewReview {rating = new.rating, body = body, liked = new.liked, consumedOn = new.consumedOn}

earliestDiaryDate :: Day
earliestDiaryDate = fromGregorian 1900 1 1

removeReview :: User -> ReviewId -> AppM NoContent
removeReview user rid = do
  removed <- runDb $ \conn -> DB.deleteReview conn user.id rid
  unless removed $ failWith err404 "Review não encontrada"
  pure NoContent

diary :: Text -> AppM [DiaryEntry]
diary name = runDb $ \conn -> DB.diaryFor conn name
