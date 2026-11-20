module Rateverything.Server
  ( application
  ) where

import Control.Monad.Reader (runReaderT)
import Network.Wai (Request)
import Network.Wai.Application.Static (defaultWebAppSettings)
import Network.Wai.Parse (defaultParseRequestBodyOptions, setMaxRequestFileSize, setMaxRequestNumFiles)
import Rateverything.Api
import Rateverything.App
import Rateverything.Auth (bearerAuthHandler)
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

type RequestContext = '[AuthHandler Request User, MultipartOptions Tmp]

application :: Env -> Application
application env =
  serveWithContext (Proxy @Api) (requestContext env) $
    apiServer env
      :<|> serveDirectoryWebApp env.config.uploadDir
      :<|> serveDirectoryWith (frontendSettings env.config.staticDir)

apiServer :: Env -> Server (PublicApi :<|> PrivateApi)
apiServer env =
  hoistServerWithContext
    (Proxy @(PublicApi :<|> PrivateApi))
    (Proxy @RequestContext)
    (`runReaderT` env)
    (publicServer :<|> privateServer)

requestContext :: Env -> Context RequestContext
requestContext env = bearerAuthHandler env.pool :. singleImageUploadOptions :. EmptyContext

singleImageUploadOptions :: MultipartOptions Tmp
singleImageUploadOptions =
  (defaultMultipartOptions (Proxy @Tmp))
    { generalOptions =
        setMaxRequestNumFiles 1 . setMaxRequestFileSize (fromIntegral maxImageBytes) $
          defaultParseRequestBodyOptions
    }

frontendSettings :: FilePath -> StaticSettings
frontendSettings staticDir =
  (defaultWebAppSettings staticDir)
    { ssIndices = [unsafeToPiece "index.html"]
    , ssMaxAge = NoCache
    }

publicServer :: ServerT PublicApi AppM
publicServer =
  register
    :<|> login
    :<|> listCategories
    :<|> searchCategory
    :<|> listCategoryItems
    :<|> getItemDetail
    :<|> getUserDiary

privateServer :: ServerT PrivateApi AppM
privateServer loggedInUser =
  pure loggedInUser
    :<|> updateAvatar loggedInUser
    :<|> logout
    :<|> createCategory loggedInUser
    :<|> importItem
    :<|> createManualItem loggedInUser
    :<|> addReview loggedInUser
    :<|> deleteReview loggedInUser
