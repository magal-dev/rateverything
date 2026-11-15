-- | Queries for reviews, ratings and the per-user diary.
module Rateverything.DB.Reviews
  ( insertReview
  , deleteReview
  , reviewsForItem
  , ratingStats
  , diaryFor
  ) where

import Data.Text (Text)
import Database.PostgreSQL.Simple
import Rateverything.DB.Connection (single)
import Rateverything.DB.Items (itemColumns)
import Rateverything.Types

-- | Columns in 'Review' field order (reviews @r@ joined with users @u@).
reviewColumns :: Query
reviewColumns = "r.id, r.user_id, u.username, u.avatar_url, r.item_id, r.rating, r.body, r.liked, r.consumed_on, r.created_at"

insertReview :: Connection -> UserId -> ItemId -> NewReview -> IO Review
insertReview conn uid iid new = do
  Only rid <-
    single "row"
      =<< query
        conn
        "INSERT INTO reviews (user_id, item_id, rating, body, liked, consumed_on) VALUES (?, ?, ?, ?, ?, ?) RETURNING id"
        (uid, iid, new.rating, new.body, new.liked, new.consumedOn)
  single "row"
    =<< query
      conn
      ("SELECT " <> reviewColumns <> " FROM reviews r JOIN users u ON u.id = r.user_id WHERE r.id = ?")
      (Only (rid :: ReviewId))

-- | Deletes a review if it belongs to the given user. Returns whether a row was removed.
deleteReview :: Connection -> UserId -> ReviewId -> IO Bool
deleteReview conn uid rid =
  (> 0) <$> execute conn "DELETE FROM reviews WHERE id = ? AND user_id = ?" (rid, uid)

reviewsForItem :: Connection -> ItemId -> IO [Review]
reviewsForItem conn iid =
  query
    conn
    ( "SELECT " <> reviewColumns <> " FROM reviews r JOIN users u ON u.id = r.user_id\
      \ WHERE r.item_id = ? ORDER BY r.created_at DESC LIMIT 100"
    )
    (Only iid)

-- | Average rating (1-10) and number of ratings for an item.
ratingStats :: Connection -> ItemId -> IO (Maybe Double, Int)
ratingStats conn iid = do
  rows <- query conn "SELECT AVG(rating)::float8, COUNT(rating)::int FROM reviews WHERE item_id = ?" (Only iid)
  pure $ case rows of
    (avg, n) : _ -> (avg, n)
    [] -> (Nothing, 0)

diaryFor :: Connection -> Text -> IO [DiaryEntry]
diaryFor conn name = do
  rows <-
    query
      conn
      ( "SELECT " <> reviewColumns <> ", " <> itemColumns <> " FROM reviews r\
        \ JOIN users u ON u.id = r.user_id JOIN items i ON i.id = r.item_id\
        \ WHERE lower(u.username) = lower(?) ORDER BY COALESCE(r.consumed_on, r.created_at) DESC, r.id DESC LIMIT 200"
      )
      (Only name)
  pure [DiaryEntry {review = r, item = i} | r :. i <- rows]
