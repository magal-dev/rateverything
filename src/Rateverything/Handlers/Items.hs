-- | Searching, viewing, importing and creating items.
module Rateverything.Handlers.Items
  ( searchCategory
  , listItems
  , itemDetail
  , importItem
  , createItem
  ) where

import Control.Monad (forM, unless, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (asks)
import Data.Foldable (for_)
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (UTCTime, getCurrentTime, toGregorian, utctDay)
import Rateverything.Api (NewItemForm (..))
import Rateverything.App
import Rateverything.Config (Config (..))
import qualified Rateverything.DB as DB
import Rateverything.Handlers.Categories (requireCategory)
import Rateverything.Providers (searchProvider)
import Rateverything.Providers.Http (ProviderError (..))
import Rateverything.Types
import Rateverything.Uploads (saveImage)
import Servant

-- | Searches the category's external provider (if any) plus items users added by hand.
searchCategory :: Text -> Text -> AppM [SearchHit]
searchCategory slug rawTerm = do
  let term = T.strip rawTerm
  when (T.null term) $ failWith err400 "Informe um termo de busca"
  category <- requireCategory slug
  external <- case category.provider of
    Nothing -> pure []
    Just provider -> do
      config <- asks (.config)
      manager <- asks (.manager)
      liftIO (searchProvider config manager provider term) >>= \case
        Left err -> do
          liftIO (TIO.putStrLn ("provider " <> provider <> " failed: " <> T.pack (show err)))
          failWith err503 $ case err of
            ProviderUnavailable _ ->
              "A busca de " <> T.toLower category.name <> " não respondeu agora. Tente novamente em alguns segundos."
            ProviderNotConfigured _ ->
              "A busca de " <> T.toLower category.name <> " ainda não foi configurada neste servidor."
        Right found -> do
          imported <- runDb $ \conn -> DB.lookupImported conn provider (map (.externalId) found)
          let known = Map.fromList imported
          pure [SearchHit {item = e, itemId = Map.lookup e.externalId known} | e <- found]
  local <- runDb $ \conn -> DB.searchLocalItems conn category.id term
  pure (external <> [SearchHit {item = asExternal i, itemId = Just i.id} | i <- local, i.source == "user"])
  where
    asExternal :: Item -> ExternalItem
    asExternal i =
      ExternalItem
        { source = i.source
        , externalId = T.pack (show i.id)
        , title = i.title
        , subtitle = i.subtitle
        , year = i.year
        , imageUrl = i.imageUrl
        , description = i.description
        }

listItems :: Text -> AppM [Item]
listItems slug = do
  category <- requireCategory slug
  runDb $ \conn -> DB.listItemsInCategory conn category.id

itemDetail :: ItemId -> AppM ItemDetail
itemDetail iid = do
  item <- runDb (`DB.findItem` iid) >>= maybe (failWith err404 "Item não encontrado") pure
  (category, (avg, count), reviews) <- runDb $ \conn ->
    (,,) <$> DB.findCategoryById conn item.categoryId <*> DB.ratingStats conn iid <*> DB.reviewsForItem conn iid
  pure ItemDetail {item = item, category = category, averageRating = avg, ratingCount = count, reviews = reviews}

-- | Stores a provider search result so it can be reviewed.
-- TODO: re-fetch the item from the provider instead of trusting the client's copy.
importItem :: Text -> ExternalItem -> AppM Item
importItem slug ext = do
  category <- requireCategory slug
  unless (category.provider == Just ext.source) $
    failWith err400 "Esse item não pertence a essa categoria"
  when (T.null (T.strip ext.title) || T.null ext.externalId) $
    failWith err400 "Item inválido"
  runDb $ \conn -> DB.upsertExternalItem conn category.id ext

-- | Creates an item by hand. Anyone can add to built-in categories (for things
-- the provider lacks); custom categories only accept items from their owner.
createItem :: User -> Text -> NewItemForm -> AppM Item
createItem user slug form = do
  category <- requireCategory slug
  when (isJust category.ownerId && category.ownerId /= Just user.id) $
    failWith err403 "Só o dono da categoria pode adicionar itens"
  let title = T.strip form.title
  when (T.null title || T.length title > 200) $ failWith err400 "O título deve ter de 1 a 200 caracteres"
  for_ form.year $ \year -> do
    -- Leaves room for announced releases.
    latest <- liftIO (maxItemYear <$> getCurrentTime)
    when (year < 1 || year > latest) $
      failWith err400 ("O ano deve ir de 1 a " <> T.pack (show latest))
  uploadDir <- asks (.config.uploadDir)
  imageUrl <- forM form.imagePath $ \path ->
    liftIO (saveImage uploadDir path) >>= either (failWith err400) pure
  runDb $ \conn ->
    DB.insertManualItem conn category.id user.id title form.subtitle form.year imageUrl form.description

maxItemYear :: UTCTime -> Int
maxItemYear now = let (y, _, _) = toGregorian (utctDay now) in fromIntegral y + 5
