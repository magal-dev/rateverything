-- | Storage of user-uploaded cover images on the local filesystem.
module Rateverything.Uploads
  ( maxImageBytes
  , saveImage
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

-- | Copies an uploaded temporary file into the upload directory under a random
-- name and returns its public URL. The format is detected from the file's
-- magic bytes, not from the client-supplied name or content type.
saveImage :: FilePath -> FilePath -> IO (Either Text Text)
saveImage uploadDir tmpPath = do
  header <- withBinaryFile tmpPath ReadMode (`BS.hGet` 12)
  case detectExtension header of
    Nothing -> pure (Left "A imagem precisa ser JPEG, PNG, GIF ou WebP")
    Just ext -> do
      name <- BS8.unpack . Base16.encode <$> (getRandomBytes 16 :: IO BS.ByteString)
      let fileName = name <> "." <> ext
      copyFile tmpPath (uploadDir </> fileName)
      pure (Right ("/uploads/" <> T.pack fileName))

detectExtension :: BS.ByteString -> Maybe String
detectExtension bytes
  | "\xFF\xD8\xFF" `BS.isPrefixOf` bytes = Just "jpg"
  | "\x89PNG\r\n\x1A\n" `BS.isPrefixOf` bytes = Just "png"
  | "GIF87a" `BS.isPrefixOf` bytes || "GIF89a" `BS.isPrefixOf` bytes = Just "gif"
  | "RIFF" `BS.isPrefixOf` bytes && BS.take 4 (BS.drop 8 bytes) == "WEBP" = Just "webp"
  | otherwise = Nothing
