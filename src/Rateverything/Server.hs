-- | Request handlers and the WAI application.
module Rateverything.Server
  ( application
  ) where

import Control.Exception (try)
import Control.Monad (forM, unless, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (asks, runReaderT)
import Data.Char (isAlphaNum, isAsciiLower, isDigit, toLower)
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Database.SQLite.Simple as SQL
import Network.Wai (Request)
import Network.Wai.Application.Static (defaultWebAppSettings)
import Network.Wai.Parse (defaultParseRequestBodyOptions, setMaxRequestFileSize, setMaxRequestNumFiles)
import Rateverything.Api
import Rateverything.App
import Rateverything.Auth
import Rateverything.Config (Config (..))
import qualified Rateverything.DB as DB
import Rateverything.Providers (searchProvider)
import Rateverything.Types
import Rateverything.Uploads (maxImageBytes, saveImage)
import Servant
import Servant.Multipart (MultipartOptions (..), Tmp, defaultMultipartOptions)
import Servant.Server.Experimental.Auth (AuthHandler)
import WaiAppStatic.Types (MaxAge (NoMaxAge), StaticSettings (..), unsafeToPiece)

application :: Env -> Application
application env =
  serveWithContext (Proxy @Api) context $
    hoistServerWithContext (Proxy @(PublicApi :<|> PrivateApi)) (Proxy @Ctx) (`runReaderT` env) (publicServer :<|> privateServer)
      :<|> serveDirectoryWebApp env.config.uploadDir
      :<|> serveDirectoryWith staticSettings
  where
    -- Frontend files keep stable names, so browsers must revalidate (via ETag)
    -- instead of caching them for a year like 'defaultWebAppSettings' does.
    staticSettings =
      (defaultWebAppSettings env.config.staticDir) {ssIndices = [unsafeToPiece "index.html"], ssMaxAge = NoMaxAge}
    context = authHandler env.config.dbPath :. multipartOptions :. EmptyContext
    multipartOptions :: MultipartOptions Tmp
    multipartOptions =
      (defaultMultipartOptions (Proxy @Tmp))
        { generalOptions =
            setMaxRequestNumFiles 1 . setMaxRequestFileSize (fromIntegral maxImageBytes) $
              defaultParseRequestBodyOptions
        }

type Ctx = '[AuthHandler Request User, MultipartOptions Tmp]

publicServer :: ServerT PublicApi AppM
publicServer =
  register
    :<|> login
    :<|> runDb DB.listCategories
    :<|> searchCategory
    :<|> listItems
    :<|> itemDetail
    :<|> diary

privateServer :: ServerT PrivateApi AppM
privateServer user =
  pure user
    :<|> updateAvatar user
    :<|> logout
    :<|> createCategory user
    :<|> importItem
    :<|> createItem user
    :<|> addReview user
    :<|> removeReview user

-- Auth -----------------------------------------------------------------------

register :: Credentials -> AppM Session
register creds = do
  let name = T.strip creds.username
  unless (validUsername name) $
    failWith err400 "Nome de usuário deve ter 3 a 30 caracteres: letras minúsculas, números ou _"
  when (T.length creds.password < 8) $
    failWith err400 "A senha precisa ter pelo menos 8 caracteres"
  hashed <- liftIO (hashPassword creds.password)
  result <- runDb $ \conn -> try (DB.insertUser conn name hashed)
  case result of
    Left (_ :: SQL.SQLError) -> failWith err409 "Esse nome de usuário já existe"
    Right user -> startSession user
  where
    validUsername n =
      T.length n >= 3 && T.length n <= 30 && T.all (\c -> isAsciiLower c || isDigit c || c == '_') n

login :: Credentials -> AppM Session
login creds = do
  found <- runDb $ \conn -> DB.findUserByName conn (T.strip creds.username)
  case found of
    Just (user, stored) | checkPassword creds.password stored -> startSession user
    _ -> failWith err401 "Usuário ou senha inválidos"

startSession :: User -> AppM Session
startSession user = do
  token <- liftIO newSessionToken
  runDb $ \conn -> DB.insertSession conn (hashToken token) user.id
  pure Session {token = token, user = user}

logout :: Text -> AppM NoContent
logout header = do
  let token = T.strip (T.drop (T.length "Bearer ") header)
  runDb $ \conn -> DB.deleteSession conn (hashToken token)
  pure NoContent

updateAvatar :: User -> AvatarForm -> AppM User
updateAvatar user form = do
  uploadDir <- asks (.config.uploadDir)
  url <- liftIO (saveImage uploadDir form.imagePath) >>= either (failWith err400) pure
  runDb $ \conn -> DB.setAvatar conn user.id url

-- Categories -----------------------------------------------------------------

requireCategory :: Text -> AppM Category
requireCategory slug =
  runDb (`DB.findCategoryBySlug` slug) >>= maybe (failWith err404 "Categoria não encontrada") pure

createCategory :: User -> NewCategory -> AppM Category
createCategory user new = do
  let name = T.strip new.name
  when (T.null name || T.length name > 60) $
    failWith err400 "O nome da categoria deve ter de 1 a 60 caracteres"
  let base = slugify name
  when (T.null base) $ failWith err400 "O nome da categoria precisa conter letras ou números"
  runDb $ \conn -> do
    slug <- firstFreeSlug conn base
    DB.insertCategory conn slug name (T.strip <$> new.description) user.id
  where
    firstFreeSlug conn base = go (1 :: Int)
      where
        go n = do
          let candidate = if n == 1 then base else base <> "-" <> T.pack (show n)
          taken <- DB.slugTaken conn candidate
          if taken then go (n + 1) else pure candidate

-- | "Vinhos Tintos & Rosés" -> "vinhos-tintos-roses"
slugify :: Text -> Text
slugify =
  T.intercalate "-" . filter (not . T.null) . T.split (== '-')
    . T.map (\c -> if isAlphaNum c && c < '\x80' then c else '-')
    . T.map (stripAccent . toLower)
  where
    stripAccent c = Map.findWithDefault c c accents
    accents =
      Map.fromList
        [ (a, plain)
        | (plain, variants) <-
            [ ('a', "áàâãäå"), ('e', "éèêë"), ('i', "íìîï"), ('o', "óòôõö")
            , ('u', "úùûü"), ('c', "ç"), ('n', "ñ")
            ]
        , a <- variants
        ]

-- Items ----------------------------------------------------------------------

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
        Left err -> failWith err502 ("Falha ao consultar o provedor: " <> err)
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
  uploadDir <- asks (.config.uploadDir)
  imageUrl <- forM form.imagePath $ \path ->
    liftIO (saveImage uploadDir path) >>= either (failWith err400) pure
  runDb $ \conn ->
    DB.insertManualItem conn category.id user.id title form.subtitle form.year imageUrl form.description

-- Reviews --------------------------------------------------------------------

addReview :: User -> ItemId -> NewReview -> AppM Review
addReview user iid new = do
  case new.rating of
    Just r | r < 1 || r > 10 -> failWith err400 "A nota deve ir de 1 a 10 (meias estrelas)"
    _ -> pure ()
  _ <- runDb (`DB.findItem` iid) >>= maybe (failWith err404 "Item não encontrado") pure
  let body = new.body >>= \b -> if T.null (T.strip b) then Nothing else Just (T.strip b)
  runDb $ \conn -> DB.insertReview conn user.id iid NewReview {rating = new.rating, body = body, liked = new.liked, consumedOn = new.consumedOn}

removeReview :: User -> ReviewId -> AppM NoContent
removeReview user rid = do
  removed <- runDb $ \conn -> DB.deleteReview conn user.id rid
  unless removed $ failWith err404 "Review não encontrada"
  pure NoContent

diary :: Text -> AppM [DiaryEntry]
diary name = runDb $ \conn -> DB.diaryFor conn name
