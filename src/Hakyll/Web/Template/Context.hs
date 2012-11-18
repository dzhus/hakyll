--------------------------------------------------------------------------------
module Hakyll.Web.Template.Context
    ( Context (..)
    , mapContext
    , field

    , defaultContext
    , bodyField
    , metadataField
    , urlField
    , pathField
    , categoryField
    , titleField
    , dateField
    , dateFieldWith
    , modificationTimeField
    , modificationTimeFieldWith
    ) where


--------------------------------------------------------------------------------
import           Control.Applicative           (Alternative (..), (<$>))
import           Control.Monad                 (msum)
import           Data.List                     (intercalate)
import qualified Data.Map                      as M
import           Data.Monoid                   (Monoid (..))
import           Data.Time.Clock               (UTCTime (..))
import           Data.Time.Format              (formatTime, parseTime)
import           System.FilePath               (takeBaseName, takeDirectory,
                                                takeFileName)
import           System.Locale                 (TimeLocale, defaultTimeLocale)


--------------------------------------------------------------------------------
import           Hakyll.Core.Compiler
import           Hakyll.Core.Compiler.Internal
import           Hakyll.Core.Identifier
import           Hakyll.Core.Item
import           Hakyll.Core.Provider
import           Hakyll.Core.Util.String       (splitAll)
import           Hakyll.Web.Urls


--------------------------------------------------------------------------------
newtype Context a = Context
    { unContext :: String -> Item a -> Compiler String
    }


--------------------------------------------------------------------------------
instance Monoid (Context a) where
    mempty                          = Context $ \_ _ -> empty
    mappend (Context f) (Context g) = Context $ \k i -> f k i <|> g k i


--------------------------------------------------------------------------------
mapContext :: (String -> String) -> Context a -> Context a
mapContext f (Context g) = Context $ \k i -> f <$> g k i


--------------------------------------------------------------------------------
field :: String -> (Item a -> Compiler String) -> Context a
field key value = Context $ \k i -> if k == key then value i else empty


--------------------------------------------------------------------------------
defaultContext :: Context String
defaultContext =
    bodyField     "body"     `mappend`
    metadataField            `mappend`
    urlField      "url"      `mappend`
    pathField     "path"     `mappend`
    categoryField "category" `mappend`
    titleField    "title"    `mappend`
    missingField


--------------------------------------------------------------------------------
bodyField :: String -> Context String
bodyField key = field key $ return . itemBody


--------------------------------------------------------------------------------
metadataField :: Context String
metadataField = Context $ \k i -> do
    metadata <- getMetadata $ itemIdentifier i
    maybe empty return $ M.lookup k metadata


--------------------------------------------------------------------------------
urlField :: String -> Context a
urlField key = field key $
    fmap (maybe empty toUrl) . getRoute . itemIdentifier


--------------------------------------------------------------------------------
pathField :: String -> Context a
pathField key = field key $ return . toFilePath . itemIdentifier


--------------------------------------------------------------------------------
categoryField :: String -> Context a
categoryField key = mapContext (takeBaseName . takeDirectory) $ pathField key


--------------------------------------------------------------------------------
titleField :: String -> Context a
titleField key = mapContext takeBaseName $ pathField key


--------------------------------------------------------------------------------
-- | When the metadata has a field called @published@ in one of the
-- following formats then this function can render the date.
--
--   * @Sun, 01 Feb 2000 13:00:00 UT@ (RSS date format)
--
--   * @2000-02-01T13:00:00Z@ (Atom date format)
--
--   * @February 1, 2000 1:00 PM@ (PM is usually uppercase)
--
--   * @February 1, 2000@ (assumes 12:00 AM for the time)
--
-- Alternatively, when the metadata has a field called @path@ in a
-- @folder/yyyy-mm-dd-title.extension@ format (the convention for pages)
-- and no @published@ metadata field set, this function can render
-- the date.
--
-- > renderDateField "date" "%B %e, %Y" "Date unknown"
--
-- Will render something like @January 32, 2010@.
--
dateField :: String     -- ^ Key in which the rendered date should be placed
          -> String     -- ^ Format to use on the date
          -> Context a  -- ^ Resulting context
dateField = dateFieldWith defaultTimeLocale


--------------------------------------------------------------------------------
-- | This is an extended version of 'dateField' that allows you to
-- specify a time locale that is used for outputting the date. For more
-- details, see 'dateField'.
dateFieldWith :: TimeLocale  -- ^ Output time locale
              -> String      -- ^ Destination key
              -> String      -- ^ Format to use on the date
              -> Context a   -- ^ Resulting context
dateFieldWith locale key format = field key $ \i -> do
    time <- getUTC locale $ itemIdentifier i
    return $ formatTime locale format time


--------------------------------------------------------------------------------
-- | Parser to try to extract and parse the time from the @published@
-- field or from the filename. See 'renderDateField' for more information.
getUTC :: TimeLocale        -- ^ Output time locale
       -> Identifier        -- ^ Input page
       -> Compiler UTCTime  -- ^ Parsed UTCTime
getUTC locale id' = do
    metadata <- getMetadata id'
    let tryField k fmt = M.lookup k metadata >>= parseTime' fmt
        fn             = takeFileName $ toFilePath id'

    maybe empty return $ msum $
        [tryField "published" fmt | fmt <- formats] ++
        [tryField "date"      fmt | fmt <- formats] ++
        [parseTime' "%Y-%m-%d" $ intercalate "-" $ take 3 $ splitAll "-" fn]
  where
    parseTime' = parseTime locale
    formats    =
        [ "%a, %d %b %Y %H:%M:%S UT"
        , "%Y-%m-%dT%H:%M:%SZ"
        , "%Y-%m-%d %H:%M:%S"
        , "%Y-%m-%d"
        , "%B %e, %Y %l:%M %p"
        , "%B %e, %Y"
        ]


--------------------------------------------------------------------------------
modificationTimeField :: String     -- ^ Key
                      -> String     -- ^ Format
                      -> Context  a -- ^ Resuting context
modificationTimeField = modificationTimeFieldWith defaultTimeLocale


--------------------------------------------------------------------------------
modificationTimeFieldWith :: TimeLocale  -- ^ Time output locale
                          -> String      -- ^ Key
                          -> String      -- ^ Format
                          -> Context a   -- ^ Resulting context
modificationTimeFieldWith locale key fmt = field key $ \i -> do
    mtime <- compilerUnsafeIO $ resourceModificationTime $ itemIdentifier i
    return $ formatTime locale fmt mtime


--------------------------------------------------------------------------------
missingField :: Context a
missingField = Context $ \k _ -> return $ "$" ++ k ++ "$"
