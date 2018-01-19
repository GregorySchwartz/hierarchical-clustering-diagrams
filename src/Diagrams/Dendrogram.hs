{-# LANGUAGE BangPatterns, FlexibleContexts, GADTs #-}
-- | This module contain functions for drawing diagrams of
-- dendrograms.
module Diagrams.Dendrogram
    ( -- * High-level interface
      -- $runnableExample
      dendrogram
    , dendrogramCustom
    , Width(..)
    , dendrogram'
    , dendrogramCustom'

      -- * Low-level interface
    , dendrogramPath
    , fixedWidth
    , variableWidth
    , X
    ) where

-- from base
import Control.Arrow (second)

-- from hierarchical-clustering
import Data.Clustering.Hierarchical (Dendrogram(..), elements)

-- from diagrams-lib
import Diagrams.Prelude hiding (elements)


-- $runnableExample
--
-- Given a dendrogram @dendro :: 'Dendrogram' a@ and a function
-- @drawItem :: a -> Diagram b V2 Double@ for drawing the items on the
-- leaves of @dendro@, just use @'dendrogram' 'Variable' drawItem
-- dendro :: Diagram b V2 Double@ to draw a diagram of @dendro@.
--
-- Runnable example which produces something like
-- <https://patch-tag.com/r/felipe/hierarchical-clustering-diagrams/snapshot/current/content/pretty/example.png>:
--
-- @
--import Data.Clustering.Hierarchical (Dendrogram(..))
--import Diagrams.Prelude (Diagram, V2 Double, atop, lw, pad, roundedRect, text, (\#))
--import Diagrams.Backend.Cairo.CmdLine (Cairo, defaultMain)
--import qualified Diagrams.Dendrogram as D
--
--main :: IO ()
--main = defaultMain diagram
--
--diagram :: Diagram Cairo V2 Double
--diagram = D.'dendrogram' 'D.Fixed' char test \# lw 0.1 \# pad 1.1
--
--char :: Char -> Diagram Cairo V2 Double
--char c = pad 1.3 $ roundedRect (1,1) 0.1 \`atop\` text [c]
--
--test :: Dendrogram Char
--test = Branch 5
--         (Branch 2
--           (Branch 1
--             (Leaf \'A\')
--             (Leaf \'B\'))
--           (Leaf \'C\'))
--         (Leaf \'D\')
-- @


-- | @dendrogram width drawItem dendro@ is a drawing of the
-- dendrogram @dendro@ using @drawItem@ to draw its leafs.  The
-- @width@ parameter controls how whether all items have the same
-- width or not ('Fixed' or 'Variable', respectively, see
-- 'Width').
--
-- Note: you should probably use 'alignT' to align your items.
dendrogram :: (Monoid m, Semigroup m, Renderable (Path V2 Double) b) =>
              Width
           -> (a -> QDiagram b V2 Double m)
           -> Dendrogram a
           -> QDiagram b V2 Double m
dendrogram = ((fst .) .) . dendrogram'

-- | Same as 'dendrogram', but specifies function to apply to path and to
-- dendrogram and leaves using functions that take in the dendrogram and leaf
-- diagrams (d,l). To leave the leaves alone and make the tree 3 times as large
-- as the leaves, for instance, we would supply
-- ((\tree items -> scaleToY (2 * height items) $ tree), curry snd).
dendrogramCustom
    :: (Monoid m, Semigroup m, Renderable (Path V2 Double) b)
    => Width
    -> (a -> QDiagram b V2 Double m)
    -> (Dendrogram a -> QDiagram b V2 Double Any -> QDiagram b V2 Double Any)
    -> (QDiagram b V2 Double m -> QDiagram b V2 Double m -> QDiagram b V2 Double m, QDiagram b V2 Double m -> QDiagram b V2 Double m -> QDiagram b V2 Double m)
    -> Dendrogram a
    -> QDiagram b V2 Double m
dendrogramCustom = ((((fst .) .) .) .) . dendrogramCustom'


-- | Same as 'dendrogram', but also returns the 'Dendrogram' with
-- positions.
dendrogram' :: (Monoid m, Semigroup m, Renderable (Path V2 Double) b) =>
               Width
            -> (a -> QDiagram b V2 Double m)
            -> Dendrogram a
            -> (QDiagram b V2 Double m, Dendrogram (a, X))
dendrogram' width_ drawItem dendro = (dia, dendroX)
  where
    dia = (stroke path_ # value mempty)
                       ===
                 (items # alignL)

    path_ = dendrogramPath (fmap snd dendroX)

    (dendroX, items) =
        case width_ of
          Fixed    -> let drawnItems = map drawItem (elements dendro)
                          w = width (head drawnItems)
                      in (fst $ fixedWidth w dendro, hcat drawnItems)
          Variable -> variableWidth drawItem dendro


-- | Same as 'dendrogram'', but specifies function to apply to path and to
-- dendrogram and leaves using functions that take in the dendrogram and leaf
-- diagrams (d,l). To leave the leaves alone and make the tree 3 times as large
-- as the leaves, for instance, we would supply
-- ((\tree items -> scaleToY (2 * height items) $ tree), curry snd).
dendrogramCustom'
    :: (Monoid m, Semigroup m, Renderable (Path V2 Double) b)
    => Width
    -> (a -> QDiagram b V2 Double m)
    -> (Dendrogram a -> QDiagram b V2 Double Any -> QDiagram b V2 Double Any)
    -> (QDiagram b V2 Double m -> QDiagram b V2 Double m -> QDiagram b V2 Double m, QDiagram b V2 Double m -> QDiagram b V2 Double m -> QDiagram b V2 Double m)
    -> Dendrogram a
    -> (QDiagram b V2 Double m, Dendrogram (a, X))
dendrogramCustom' width_ drawItem drawPath (drawTree, drawItems) dendro =
    (dia, dendroX)
  where
    dia = (drawTree path_ items_)
                       ===
                 (drawItems path_ items_)

    path_ = dendrogramPathCustom drawPath dendroX # value mempty
    items_ = items # alignL

    (dendroX, items) =
        case width_ of
          Fixed    -> let drawnItems = map drawItem (elements dendro)
                          w = width (head drawnItems)
                      in (fst $ fixedWidth w dendro, hcat drawnItems)
          Variable -> variableWidth drawItem dendro


-- | The width of the items on the leafs of a dendrogram.
data Width =
      Fixed
      -- ^ @Fixed@ assumes that all items have a fixed width
      -- (which is automatically calculated).  This mode is
      -- faster than @Variable@, especially when you have many
      -- items.
    | Variable
      -- ^ @Variable@ does not assume that all items have a fixed
      -- width, so each item may have a different width.  This
      -- mode is slower since it has to calculate the width of
      -- each item separately.


-- | A dendrogram path that can be 'stroke'@d@ later.  This function
-- assumes that the 'Leaf'@s@ of your 'Dendrogram' are already in
-- the right position.
dendrogramPath :: Dendrogram X -> Path V2 Double
dendrogramPath = mconcat . fst . go []
    where
      go acc (Leaf x)       = (acc, (x, 0))
      go acc (Branch d l r) = (path : acc'', pos)
        where
          (acc',  (!xL, !yL)) = go acc  l
          (acc'', (!xR, !yR)) = go acc' r

          path = fromVertices [ p2 (xL, yL)
                              , p2 (xL, d)
                              , p2 (xR, d)
                              , p2 (xR, yR)]
          pos  = (xL + (xR - xL) / 2, d)
          
-- | A dendrogram diagram. This function assumes that the 'Leaf'@s@ of your
-- 'Dendrogram' are already in the right position. Allows for a custom function
-- to apply to each path.
dendrogramPathCustom
    :: (Renderable (Path V2 Double) b)
    => (Dendrogram a -> QDiagram b V2 Double Any -> QDiagram b V2 Double Any)
    -> Dendrogram (a, X)
    -> QDiagram b V2 Double Any
dendrogramPathCustom f = mconcat . fst . go []
    where
      go acc (Leaf (_, x))    = (acc, (x, 0))
      go acc (Branch d l r) = (path : acc'', pos)
        where
          (acc',  (!xL, !yL)) = go acc  l
          (acc'', (!xR, !yR)) = go acc' r

          path = ( f (fmap fst l)
                 . strokeP
                 $ fromVertices [ p2 (xL, yL)
                                , p2 (xL, d)
                                , p2 (xL + ((xR - xL) / 2), d)
                                ]
                 )
              <> ( f (fmap fst r)
                 . strokeP
                 $ fromVertices [ p2 (xR - ((xR - xL) / 2), d)
                                , p2 (xR, d)
                                , p2 (xR, yR)
                                ]
                 )
          pos  = (xL + (xR - xL) / 2, d)


-- | The horizontal position of a dendrogram Leaf.
type X = Double


-- | @fixedWidth w@ positions the 'Leaf'@s@ of a 'Dendrogram'
-- assuming that they have the same width @w@.  Also returns the
-- total width.
fixedWidth :: Double -> Dendrogram a -> (Dendrogram (a, X), Double)
fixedWidth w = second (subtract half_w) . go half_w
    where
      half_w = w/2
      go !y (Leaf datum)   = (Leaf (datum, y), y + w)
      go !y (Branch d l r) = (Branch d l' r', y'')
          where
            (l', !y')  = go y  l
            (r', !y'') = go y' r


-- | @variableWidth draw@ positions the 'Leaf'@s@ of a
-- 'Dendrogram' according to the diagram generated by 'draw'.
-- Each 'Leaf' may have a different width.  Also returns the
-- resulting diagram having all 'Leaf'@s@ drawn side-by-side.
--
-- Note: you should probably use 'alignT' to align your items.
variableWidth :: (Semigroup m, Monoid m) =>
                 (a -> QDiagram b V2 Double m)
              -> Dendrogram a
              -> (Dendrogram (a, X), QDiagram b V2 Double m)
variableWidth draw = finish . go 0 []
    where
      go !y acc (Leaf a) = (Leaf (a,y'), y'', dia : acc)
          where
            dia  = draw a
            !w   = width dia
            !y'  = y + w/2
            !y'' = y + w
      go !y acc (Branch d l r) = (Branch d l' r', y'', acc'')
          where
            (l', !y',  acc'') = go y  acc' l -- yes, this is acc'
            (r', !y'', acc')  = go y' acc r
      finish (dendro, _, dias) = (dendro, hcat dias)
      -- We used to concatenate diagrams inside 'go' using (|||).
      -- However, pathological dendrograms (such as those created
      -- using single linkage) may be highly unbalanced, creating
      -- a performance problem for 'variableWidth'.
