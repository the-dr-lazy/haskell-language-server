{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}
module Development.IDE.Types.Exports
(
    IdentInfo(..),
    ExportsMap(..),
    createExportsMap,
    createExportsMapMg,
    createExportsMapTc
) where

import Avail (AvailInfo(..))
import Control.DeepSeq (NFData(..))
import Data.Text (pack, Text)
import Development.IDE.GHC.Compat
import Development.IDE.GHC.Util
import Data.HashMap.Strict (HashMap)
import GHC.Generics (Generic)
import Name
import FieldLabel (flSelector)
import qualified Data.HashMap.Strict as Map
import GhcPlugins (IfaceExport, ModGuts(..))
import Data.HashSet (HashSet)
import qualified Data.HashSet as Set
import Data.Bifunctor (Bifunctor(second))
import Data.Hashable (Hashable)
import TcRnTypes(TcGblEnv(..))

newtype ExportsMap = ExportsMap
    {getExportsMap :: HashMap IdentifierText (HashSet IdentInfo)}
    deriving newtype (Monoid, NFData, Show)

instance Semigroup ExportsMap where
    ExportsMap a <> ExportsMap b = ExportsMap $ Map.unionWith (<>) a b

type IdentifierText = Text

data IdentInfo = IdentInfo
    { name :: !Text
    , rendered :: Text
    , parent :: !(Maybe Text)
    , isDatacon :: !Bool
    , moduleNameText :: !Text
    }
    deriving (Generic, Show)
    deriving anyclass Hashable

instance Eq IdentInfo where
    a == b = name a == name b
          && parent a == parent b
          && isDatacon a == isDatacon b
          && moduleNameText a == moduleNameText b

instance NFData IdentInfo where
    rnf IdentInfo{..} =
        -- deliberately skip the rendered field
        rnf name `seq` rnf parent `seq` rnf isDatacon `seq` rnf moduleNameText

mkIdentInfos :: Text -> AvailInfo -> [IdentInfo]
mkIdentInfos mod (Avail n) =
    [IdentInfo (pack (prettyPrint n)) (pack (printName n)) Nothing (isDataConName n) mod]
mkIdentInfos mod (AvailTC parent (n:nn) flds)
    -- Following the GHC convention that parent == n if parent is exported
    | n == parent
    = [ IdentInfo (pack (prettyPrint n)) (pack (printName n)) (Just $! parentP) (isDataConName n) mod
        | n <- nn ++ map flSelector flds
      ] ++
      [ IdentInfo (pack (prettyPrint n)) (pack (printName n)) Nothing (isDataConName n) mod]
    where
        parentP = pack $ printName parent

mkIdentInfos mod (AvailTC _ nn flds)
    = [ IdentInfo (pack (prettyPrint n)) (pack (printName n)) Nothing (isDataConName n) mod
        | n <- nn ++ map flSelector flds
      ]

createExportsMap :: [ModIface] -> ExportsMap
createExportsMap = ExportsMap . Map.fromListWith (<>) . concatMap doOne
  where
    doOne mi = concatMap (fmap (second Set.fromList) . unpackAvail mn) (mi_exports mi)
      where
        mn = moduleName $ mi_module mi

createExportsMapMg :: [ModGuts] -> ExportsMap
createExportsMapMg = ExportsMap . Map.fromListWith (<>) . concatMap doOne
  where
    doOne mi = concatMap (fmap (second Set.fromList) . unpackAvail mn) (mg_exports mi)
      where
        mn = moduleName $ mg_module mi

createExportsMapTc :: [TcGblEnv] -> ExportsMap
createExportsMapTc = ExportsMap . Map.fromListWith (<>) . concatMap doOne
  where
    doOne mi = concatMap (fmap (second Set.fromList) . unpackAvail mn) (tcg_exports mi)
      where
        mn = moduleName $ tcg_mod mi

unpackAvail :: ModuleName -> IfaceExport -> [(Text, [IdentInfo])]
unpackAvail !(pack . moduleNameString -> mod) = map f . mkIdentInfos mod
  where
    f id@IdentInfo {..} = (name, [id])
