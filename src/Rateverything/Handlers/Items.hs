module Rateverything.Handlers.Items
  ( searchCategory
  , listCategoryItems
  , getItemDetail
  , importItem
  , createManualItem
  ) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (asks)
import Data.Foldable (for_)
import qualified Data.Map.Strict as Map
import Data.Maybe (isNothing)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (getCurrentTime, toGregorian, utctDay)
import Rateverything.Api (NewItemForm (..))
import Rateverything.App
import qualified Rateverything.DB as DB
import Rateverything.Handlers.Categories (requireCategory)
import Rateverything.Providers (searchProvider)
import Rateverything.Providers.Http (ProviderError (..))
import Rateverything.Types
import Servant

searchCategory :: Text -> Text -> AppM [SearchHit]
searchCategory slug rawSearchTerm = do
  let searchTerm = T.strip rawSearchTerm
  failUnless (not (T.null searchTerm)) err400 "Informe um termo de busca"
  category <- requireCategory slug
  providerHits <- case category.provider of
    Nothing -> pure []
    Just providerKey -> searchExternalCatalog category providerKey searchTerm
  manualHits <- searchManualItems category searchTerm
  pure (providerHits <> manualHits)

searchExternalCatalog :: Category -> Text -> Text -> AppM [SearchHit]
searchExternalCatalog category providerKey searchTerm = do
  config <- asks (.config)
  manager <- asks (.manager)
  liftIO (searchProvider config manager providerKey searchTerm) >>= \case
    Left providerError -> do
      liftIO (TIO.putStrLn ("provider " <> providerKey <> " failed: " <> T.pack (show providerError)))
      failWith err503 (providerFailureMessage category providerError)
    Right externalItems -> markAlreadyImported providerKey externalItems

providerFailureMessage :: Category -> ProviderError -> Text
providerFailureMessage category providerError =
  "A busca de " <> T.toLower category.name <> case providerError of
    ProviderUnavailable _ -> " não respondeu agora. Tente novamente em alguns segundos."
    ProviderNotConfigured _ -> " ainda não foi configurada neste servidor."

markAlreadyImported :: Text -> [ExternalItem] -> AppM [SearchHit]
markAlreadyImported providerKey externalItems = do
  importedPairs <- runDb $ \conn ->
    DB.findImportedItemIds conn providerKey (map (.externalId) externalItems)
  let localIdByExternalId = Map.fromList importedPairs
  pure
    [ SearchHit {item = externalItem, itemId = Map.lookup externalItem.externalId localIdByExternalId}
    | externalItem <- externalItems
    ]

searchManualItems :: Category -> Text -> AppM [SearchHit]
searchManualItems category searchTerm = do
  matchingItems <- runDb $ \conn -> DB.searchItemsInCategory conn category.id searchTerm
  pure
    [ SearchHit {item = asExternalItem localItem, itemId = Just localItem.id}
    | localItem <- matchingItems
    , localItem.source == "user"
    ]

asExternalItem :: Item -> ExternalItem
asExternalItem localItem =
  ExternalItem
    { source = localItem.source
    , externalId = T.pack (show localItem.id)
    , title = localItem.title
    , subtitle = localItem.subtitle
    , year = localItem.year
    , imageUrl = localItem.imageUrl
    , description = localItem.description
    }

listCategoryItems :: Text -> AppM [Item]
listCategoryItems slug = do
  category <- requireCategory slug
  runDb $ \conn -> DB.listRecentItemsInCategory conn category.id

getItemDetail :: ItemId -> AppM ItemDetail
getItemDetail itemId = do
  item <- runDb (`DB.findItem` itemId) `orFailWith` (err404, "Item não encontrado")
  (category, (averageRating, ratingCount), reviews) <- runDb $ \conn ->
    (,,)
      <$> DB.findCategoryById conn item.categoryId
      <*> DB.ratingSummaryOfItem conn itemId
      <*> DB.listReviewsOfItem conn itemId
  pure
    ItemDetail
      { item = item
      , category = category
      , averageRating = averageRating
      , ratingCount = ratingCount
      , reviews = reviews
      }

importItem :: Text -> ExternalItem -> AppM Item
importItem slug externalItem = do
  category <- requireCategory slug
  failUnless (category.provider == Just externalItem.source) err400
    "Esse item não pertence a essa categoria"
  failUnless (isValidExternalItem externalItem) err400 "Item inválido"
  runDb $ \conn -> DB.upsertExternalItem conn category.id externalItem

isValidExternalItem :: ExternalItem -> Bool
isValidExternalItem externalItem =
  not (T.null (T.strip externalItem.title)) && not (T.null externalItem.externalId)

createManualItem :: User -> Text -> NewItemForm -> AppM Item
createManualItem user slug form = do
  category <- requireCategory slug
  failUnless (canAddItemsTo user category) err403 "Só o dono da categoria pode adicionar itens"
  let title = T.strip form.title
  failUnless (isValidItemTitle title) err400 "O título deve ter de 1 a 200 caracteres"
  for_ form.year validateItemYear
  imageUrl <- traverse saveUploadedImage form.imagePath
  runDb $ \conn ->
    DB.insertManualItem
      conn
      NewManualItem
        { categoryId = category.id
        , createdBy = user.id
        , title = title
        , subtitle = form.subtitle
        , year = form.year
        , imageUrl = imageUrl
        , description = form.description
        }

canAddItemsTo :: User -> Category -> Bool
canAddItemsTo user category = isNothing category.ownerId || category.ownerId == Just user.id

isValidItemTitle :: Text -> Bool
isValidItemTitle title = not (T.null title) && T.length title <= 200

validateItemYear :: Int -> AppM ()
validateItemYear year = do
  latestYear <- liftIO latestAllowedItemYear
  failUnless (year >= 1 && year <= latestYear) err400
    ("O ano deve ir de 1 a " <> T.pack (show latestYear))

latestAllowedItemYear :: IO Int
latestAllowedItemYear = do
  (currentYear, _, _) <- toGregorian . utctDay <$> getCurrentTime
  pure (fromIntegral currentYear + yearsAheadForAnnouncedReleases)

yearsAheadForAnnouncedReleases :: Int
yearsAheadForAnnouncedReleases = 5
