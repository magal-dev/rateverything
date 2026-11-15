-- | The WAI application: connects each route in "Rateverything.Api" to its
-- handler (under @Handlers/@) and serves uploads and the frontend.
module Rateverything.Server
  ( application
  ) where

import Control.Monad.Reader (runReaderT)
import Network.Wai (Request)
import Network.Wai.Application.Static (defaultWebAppSettings)
import Network.Wai.Parse (defaultParseRequestBodyOptions, setMaxRequestFileSize, setMaxRequestNumFiles)
import Rateverything.Api
import Rateverything.App
import Rateverything.Auth (authHandler)
import Rateverything.Config (Config (..))
import Rateverything.Handlers.Auth
import Rateverything.Handlers.Categories
import Rateverything.Handlers.Items
import Rateverything.Handlers.Reviews
import Rateverything.Types (User)
import Rateverything.Uploads (maxImageBytes)
import Servant
import Servant.Multipart (MultipartOptions (..), Tmp, defaultMultipartOptions)
import Servant.Server.Experimental.Auth (AuthHandler)
import WaiAppStatic.Types (MaxAge (NoCache), StaticSettings (..), unsafeToPiece)

application :: Env -> Application
application env =
  serveWithContext (Proxy @Api) context $
    hoistServerWithContext (Proxy @(PublicApi :<|> PrivateApi)) (Proxy @Ctx) (`runReaderT` env) (publicServer :<|> privateServer)
      :<|> serveDirectoryWebApp env.config.uploadDir
      :<|> serveDirectoryWith staticSettings
  where
    -- Frontend files keep stable names, so browsers must revalidate (via ETag)
    -- on every load. Without an explicit no-cache they would fall back to
    -- heuristic caching and keep serving an old app.js.
    staticSettings =
      (defaultWebAppSettings env.config.staticDir) {ssIndices = [unsafeToPiece "index.html"], ssMaxAge = NoCache}
    context = authHandler env.pool :. multipartOptions :. EmptyContext
    multipartOptions :: MultipartOptions Tmp
    multipartOptions =
      (defaultMultipartOptions (Proxy @Tmp))
        { generalOptions =
            setMaxRequestNumFiles 1 . setMaxRequestFileSize (fromIntegral maxImageBytes) $
              defaultParseRequestBodyOptions
        }

type Ctx = '[AuthHandler Request User, MultipartOptions Tmp]

-- | Same order as the routes in 'PublicApi'.
publicServer :: ServerT PublicApi AppM
publicServer =
  register
    :<|> login
    :<|> listCategories
    :<|> searchCategory
    :<|> listItems
    :<|> itemDetail
    :<|> diary

-- | Same order as the routes in 'PrivateApi'; every handler gets the logged-in user.
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
