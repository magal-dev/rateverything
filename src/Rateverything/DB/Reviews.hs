module Rateverything.DB.Reviews
  ( insertReview
  , deleteOwnReview
  , listReviewsOfItem
  , ratingSummaryOfItem
  , diaryOfUser
  ) where

import Data.Text (Text)
import Database.PostgreSQL.Simple
import Rateverything.DB.Connection (firstRowOrFail)
import Rateverything.DB.Items (itemColumns)
import Rateverything.Types

reviewColumns :: Query
reviewColumns =
  "r.id, r.user_id, u.username, u.avatar_url, r.item_id, r.rating, r.body, r.liked, r.consumed_on, r.created_at"

selectReviewsWithAuthor :: Query
selectReviewsWithAuthor = "SELECT " <> reviewColumns <> " FROM reviews r JOIN users u ON u.id = r.user_id"

insertReview :: Connection -> UserId -> ItemId -> NewReview -> IO Review
insertReview conn userId itemId newReview = do
  Only insertedReviewId <-
    firstRowOrFail "row"
      =<< query
        conn
        "INSERT INTO reviews (user_id, item_id, rating, body, liked, consumed_on)\
        \ VALUES (?, ?, ?, ?, ?, ?) RETURNING id"
        (userId, itemId, newReview.rating, newReview.body, newReview.liked, newReview.consumedOn)
  firstRowOrFail "row"
    =<< query conn (selectReviewsWithAuthor <> " WHERE r.id = ?") (Only (insertedReviewId :: ReviewId))

deleteOwnReview :: Connection -> UserId -> ReviewId -> IO Bool
deleteOwnReview conn userId reviewId = do
  deletedRowCount <- execute conn "DELETE FROM reviews WHERE id = ? AND user_id = ?" (reviewId, userId)
  pure (deletedRowCount > 0)

listReviewsOfItem :: Connection -> ItemId -> IO [Review]
listReviewsOfItem conn itemId =
  query
    conn
    (selectReviewsWithAuthor <> " WHERE r.item_id = ? ORDER BY r.created_at DESC LIMIT 100")
    (Only itemId)

ratingSummaryOfItem :: Connection -> ItemId -> IO (Maybe Double, Int)
ratingSummaryOfItem conn itemId = do
  rows <- query conn "SELECT AVG(rating)::float8, COUNT(rating)::int FROM reviews WHERE item_id = ?" (Only itemId)
  pure $ case rows of
    (averageRating, ratingCount) : _ -> (averageRating, ratingCount)
    [] -> (Nothing, 0)

diaryOfUser :: Connection -> Text -> IO [DiaryEntry]
diaryOfUser conn username = do
  rows <-
    query
      conn
      ( "SELECT " <> reviewColumns <> ", " <> itemColumns <> " FROM reviews r\
        \ JOIN users u ON u.id = r.user_id JOIN items i ON i.id = r.item_id\
        \ WHERE lower(u.username) = lower(?)\
        \ ORDER BY COALESCE(r.consumed_on, r.created_at) DESC, r.id DESC LIMIT 200"
      )
      (Only username)
  pure [DiaryEntry {review = review, item = item} | review :. item <- rows]
