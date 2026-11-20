module Rateverything.Handlers.Categories
  ( listCategories
  , createCategory
  , requireCategory
  , slugify
  ) where

import Data.Char (isAlphaNum, isAscii, toLower)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Database.PostgreSQL.Simple (Connection)
import Rateverything.App
import qualified Rateverything.DB as DB
import Rateverything.Types
import Servant

listCategories :: AppM [Category]
listCategories = runDb DB.listCategories

requireCategory :: Text -> AppM Category
requireCategory slug =
  runDb (`DB.findCategoryBySlug` slug) `orFailWith` (err404, "Categoria não encontrada")

createCategory :: User -> NewCategory -> AppM Category
createCategory user newCategory = do
  let name = T.strip newCategory.name
  failUnless (isValidCategoryName name) err400 "O nome da categoria deve ter de 1 a 60 caracteres"
  let baseSlug = slugify name
  failUnless (not (T.null baseSlug)) err400 "O nome da categoria precisa conter letras ou números"
  runDb $ \conn -> do
    slug <- firstAvailableSlug conn baseSlug
    DB.insertCategory conn slug name (T.strip <$> newCategory.description) user.id

isValidCategoryName :: Text -> Bool
isValidCategoryName name = not (T.null name) && T.length name <= maxCategoryNameLength

maxCategoryNameLength :: Int
maxCategoryNameLength = 60

firstAvailableSlug :: Connection -> Text -> IO Text
firstAvailableSlug conn baseSlug = tryAttempt 1
  where
    tryAttempt attemptNumber = do
      let candidate = numberedSlug baseSlug attemptNumber
      taken <- DB.isSlugTaken conn candidate
      if taken then tryAttempt (attemptNumber + 1) else pure candidate

numberedSlug :: Text -> Int -> Text
numberedSlug baseSlug 1 = baseSlug
numberedSlug baseSlug attemptNumber = baseSlug <> "-" <> T.pack (show attemptNumber)

slugify :: Text -> Text
slugify =
  T.intercalate "-"
    . filter (not . T.null)
    . T.split (not . isSlugCharacter)
    . T.map (removeAccent . toLower)

isSlugCharacter :: Char -> Bool
isSlugCharacter character = isAscii character && isAlphaNum character

removeAccent :: Char -> Char
removeAccent character = Map.findWithDefault character character unaccentedLetters

unaccentedLetters :: Map.Map Char Char
unaccentedLetters =
  Map.fromList
    [ (accentedLetter, plainLetter)
    | (plainLetter, accentedVariants) <-
        [ ('a', "áàâãäå"), ('e', "éèêë"), ('i', "íìîï"), ('o', "óòôõö")
        , ('u', "úùûü"), ('c', "ç"), ('n', "ñ")
        ]
    , accentedLetter <- accentedVariants
    ]
