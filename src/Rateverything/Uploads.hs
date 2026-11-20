module Rateverything.Uploads
  ( maxImageBytes
  , copyImageToUploads
  ) where

import Crypto.Random (getRandomBytes)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base16 as Base16
import qualified Data.ByteString.Char8 as BS8
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (copyFile)
import System.FilePath ((</>))
import System.IO (IOMode (ReadMode), withBinaryFile)

maxImageBytes :: Int
maxImageBytes = 5 * 1024 * 1024

copyImageToUploads :: FilePath -> FilePath -> IO (Either Text Text)
copyImageToUploads uploadDir temporaryPath = do
  fileHeader <- withBinaryFile temporaryPath ReadMode (`BS.hGet` magicBytesToInspect)
  case imageExtensionFromMagicBytes fileHeader of
    Nothing -> pure (Left "A imagem precisa ser JPEG, PNG, GIF ou WebP")
    Just extension -> do
      baseName <- randomHexName
      let fileName = baseName <> "." <> extension
      copyFile temporaryPath (uploadDir </> fileName)
      pure (Right (publicUploadUrl fileName))

magicBytesToInspect :: Int
magicBytesToInspect = 12

randomHexName :: IO String
randomHexName = BS8.unpack . Base16.encode <$> (getRandomBytes 16 :: IO BS.ByteString)

publicUploadUrl :: FilePath -> Text
publicUploadUrl fileName = "/uploads/" <> T.pack fileName

imageExtensionFromMagicBytes :: BS.ByteString -> Maybe String
imageExtensionFromMagicBytes bytes
  | "\xFF\xD8\xFF" `BS.isPrefixOf` bytes = Just "jpg"
  | "\x89PNG\r\n\x1A\n" `BS.isPrefixOf` bytes = Just "png"
  | "GIF87a" `BS.isPrefixOf` bytes || "GIF89a" `BS.isPrefixOf` bytes = Just "gif"
  | "RIFF" `BS.isPrefixOf` bytes && webpMarker == "WEBP" = Just "webp"
  | otherwise = Nothing
  where
    webpMarker = BS.take 4 (BS.drop 8 bytes)
