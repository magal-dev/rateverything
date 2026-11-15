-- | Listing and creating categories.
module Rateverything.Handlers.Categories
  ( listCategories
  , createCategory
  , requireCategory
  , slugify
  ) where

import Control.Monad (when)
import Data.Char (isAlphaNum, toLower)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Rateverything.App
import qualified Rateverything.DB as DB
import Rateverything.Types
import Servant

listCategories :: AppM [Category]
listCategories = runDb DB.listCategories

-- | The category with this slug, or a 404.
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
    -- "vinhos", then "vinhos-2", "vinhos-3", ...
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
