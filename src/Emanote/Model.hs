{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

module Emanote.Model where

import Control.Lens.Operators as Lens ((%~), (^.))
import Control.Lens.TH (makeLenses)
import qualified Data.Aeson as Aeson
import Data.Default (Default (..))
import Data.IxSet.Typed ((@+), (@=))
import qualified Data.IxSet.Typed as Ix
import qualified Data.Set as Set
import Data.Tree (Tree)
import Ema (Slug)
import qualified Ema.Helper.PathTree as PathTree
import Emanote.Model.Note
  ( IxNote,
    Note (Note),
    SelfRef (SelfRef),
    noteRoute,
    noteTitle,
  )
import Emanote.Model.Rel (IxRel)
import qualified Emanote.Model.Rel as Rel
import Emanote.Model.SData (IxSData, SData (SData))
import Emanote.Route (MarkdownRoute)
import qualified Emanote.Route as R
import qualified Emanote.Route.Ext as Ext
import qualified Emanote.Route.WikiLinkTarget as WL
import Heist.Extra.TemplateState (TemplateState)
import Text.Pandoc.Definition (Pandoc (..))
import qualified Text.Pandoc.Definition as B

data Model = Model
  { _modelNotes :: IxNote,
    _modelRels :: IxRel,
    _modelData :: IxSData,
    _modelDataDefault :: Aeson.Value,
    _modelStaticFiles :: Set FilePath,
    _modelNav :: [Tree Slug],
    _modelHeistTemplate :: TemplateState
  }

makeLenses ''Model

instance Default Model where
  def = Model Ix.empty Ix.empty Ix.empty Aeson.Null mempty mempty def

modelInsertMarkdown :: MarkdownRoute -> (Aeson.Value, Pandoc) -> Model -> Model
modelInsertMarkdown k v =
  modelNotes %~ Ix.updateIx k note
    >>> modelRels %~ (Ix.deleteIx k >>> Ix.insertList (Rel.extractRels note))
    >>> modelNav %~ PathTree.treeInsertPath (R.unRoute k)
  where
    note = Note (snd v) (fst v) k

modelDeleteMarkdown :: MarkdownRoute -> Model -> Model
modelDeleteMarkdown k =
  modelNotes %~ Ix.deleteIx k
    >>> modelRels %~ Ix.deleteIx k
    >>> modelNav %~ PathTree.treeDeletePath (R.unRoute k)

modelInsertData :: R.Route Ext.Yaml -> Aeson.Value -> Model -> Model
modelInsertData r v =
  modelData %~ Ix.updateIx r (SData v r)

modelDeleteData :: R.Route Ext.Yaml -> Model -> Model
modelDeleteData k =
  modelData %~ Ix.deleteIx k

modelLookup :: MarkdownRoute -> Model -> Maybe Note
modelLookup k =
  Ix.getOne . Ix.getEQ k . _modelNotes

modelLookupTitle :: MarkdownRoute -> Model -> Text
modelLookupTitle r =
  maybe (R.routeFileBase r) noteTitle . modelLookup r

modelLookupRouteByWikiLink :: WL.WikiLinkTarget -> Model -> [MarkdownRoute]
modelLookupRouteByWikiLink wl model =
  -- TODO: Also lookup wiki links to *directories* without an associated zettel.
  -- Eg: my [[Public Post Ideas]]
  fmap (^. noteRoute) . Ix.toList $ (model ^. modelNotes) @= SelfRef wl

modelLookupBacklinks :: MarkdownRoute -> Model -> [(MarkdownRoute, NonEmpty [B.Block])]
modelLookupBacklinks r model =
  let refsToSelf =
        Set.fromList $
          (Left <$> toList (WL.allowedWikiLinkTargets r))
            <> [Right r]
      backlinks = Ix.toList $ (model ^. modelRels) @+ toList refsToSelf
   in backlinks <&> \rel ->
        (rel ^. Rel.relFrom, rel ^. Rel.relCtx)

staticRoutes :: Model -> [Either FilePath MarkdownRoute]
staticRoutes model =
  let mdRoutes = (fmap (^. noteRoute) . Ix.toList . (^. modelNotes)) model
      staticFiles = Set.toList $ model ^. modelStaticFiles
   in fmap Right mdRoutes <> fmap Left staticFiles
