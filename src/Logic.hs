{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Logic (
    CmdKey(..), Cmd'(..), Cmd, Cmds,
    AbstractPos(..),
    AppState(..),
    initialAppState, initialCommands, isSelected, key2dna,
    selectedDNA,
    Event(..), handle,
    ) where

import Control.Applicative
import qualified Data.Map as M
import Data.List

import DNA
import qualified SelectTwo as S2
import PresentationCmds (Cmds, Cmd, Cmd'(..))

-- Lets keep the keys separate from the sequential indices
newtype Key = Key Int deriving (Num, Eq, Ord, Enum)

type Seed = Int

data AppState = AppState
    { seed :: Seed
    , dnas :: M.Map Key DNA
    , drag :: Maybe DNA
    , dragOn :: Maybe DNA
    , sel :: S2.SelectTwo Key
    }

-- Events passed on to the presentation layer
data AbstractPos = MainPos | SmallPos Int Int | DeletedPos Int Int

-- The main instance can be selected, the preview instance not
data CmdKey = PreviewInstance DNA | MainInstance DNA
    deriving (Eq, Ord, Show)

key2dna :: CmdKey -> DNA
key2dna (MainInstance d) = d
key2dna (PreviewInstance d) = d

initialAppState :: Seed -> AppState
initialAppState seed = AppState {..}
  where
    dnas = M.fromList $ zipWith (\n d -> (n,d)) [0..] initialDNAs
    sel = S2.duolton 0 1
    drag = Nothing
    dragOn = Nothing


dnaAtKey :: AppState -> Key -> DNA
dnaAtKey AppState{..} k = dnas M.! k

newDNA :: AppState -> Maybe DNA
newDNA as@AppState{..}
    | S2.TwoSelected x y <- sel
    = Just $ crossover seed (as `dnaAtKey` x) (as `dnaAtKey` y)
    | Just x <- drag, Just y <- dragOn
    = Just $ crossover seed x y
    | otherwise = Nothing

selectedDNA :: AppState -> Maybe DNA
selectedDNA as@AppState{..}
    | S2.OneSelected x <- sel = Just $ as `dnaAtKey` x
    | otherwise = Nothing

preview :: AppState -> Maybe DNA
preview as = newDNA as <|> selectedDNA as

isSelected :: AppState -> DNA -> Bool
isSelected as@AppState{..} = if
    | S2.TwoSelected x y <- sel -> \d -> d `elem` [as `dnaAtKey` x, as `dnaAtKey` y]
    | S2.OneSelected x <- sel -> \d -> d == (as `dnaAtKey` x)
    | Just x <- drag, Just y <- dragOn -> \d -> d `elem` [x,y]
    | otherwise -> const False

moveAllSmall :: AppState -> Cmds CmdKey AbstractPos
moveAllSmall as =
    [ (MainInstance d, MoveTo (SmallPos c n))
    | (n, d) <- zip [0..] (M.elems (dnas as))
    ]
  where
    c = length (dnas as)

moveOneSmall :: AppState -> DNA -> Cmd CmdKey AbstractPos
moveOneSmall as d = (MainInstance d, MoveTo (SmallPos c n))
  where
    c = length (dnas as)
    Just n = elemIndex d (M.elems (dnas as))

moveMain :: AppState -> Cmds CmdKey AbstractPos
moveMain as =
    [ (PreviewInstance d, MoveTo MainPos)
    | Just d <- return $ newDNA as ]

initialCommands :: AppState -> Cmds CmdKey AbstractPos
initialCommands as = moveAllSmall as ++ moveMain as

data Event
    = Click CmdKey
    | BeginDrag CmdKey
    | DragDelta (Double, Double)
    | DragOn CmdKey
    | DragOff CmdKey
    | EndDrag
    | CancelDrag
    | Delete

handle :: AppState -> Event -> (AppState, Cmds CmdKey AbstractPos)
handle as@AppState{..} e = case e of
    -- Adding a new pattern
    Click (PreviewInstance d)
        | Just new <- newDNA as, d == new
        , new `notElem` M.elems dnas
        , let newKey = succ (fst (M.findMax dnas))
        , let dnas' = M.insert newKey new dnas
        , let as' = as { sel = S2.empty, dnas = dnas' }
        -> ( as'
           , [ (PreviewInstance new, Remove)
             , (MainInstance new, SummonAt MainPos)
             ] ++
             moveAllSmall as'
           )
    -- Clicking an already added pattern
    Click (PreviewInstance d)
        | Just new <- newDNA as
        , d == new
        , Just i <- elemIndex d (M.elems dnas)
        -> -- send preview move event
           ( as { sel = S2.empty, dnas = dnas }
           , [ (PreviewInstance new, FadeOut (SmallPos (length dnas) i)) ] )

    -- Changing selection
    Click (MainInstance d)
        | (k:_) <- [ k | (k,d') <- M.toList dnas, d == d' ]
        -> let as' = as { sel = S2.flip sel k , drag = Nothing }
           in
           ( as'
           , [ (PreviewInstance d', Remove)
             | Just d' <- pure $ preview as
             ] ++
             [ (PreviewInstance d', SummonAt MainPos)
             | Just d' <- pure $ preview as'
             ]
           )

    -- Beginning a drag-and-drop action
    BeginDrag (MainInstance d)
        -> ( as { drag = Just d }
           , case sel of
               S2.OneSelected k_old -> [ (PreviewInstance (as `dnaAtKey` k_old), Remove ) ]
               S2.TwoSelected {} | Just old <- newDNA as -> [ (PreviewInstance old, Remove) ]
               _ -> []
           )

    DragDelta p
        | Just d <- drag
        -> ( as { sel = S2.empty }, [ (MainInstance d, ShiftPos p) ] )

    DragOn (MainInstance d')
        | Just _ <- drag
        , let as' = as { dragOn = Just d' }
        -> ( as', [ (PreviewInstance new, SummonAt MainPos) | Just new <- pure $ newDNA as' ] )

    DragOff (MainInstance _')
        | Just _ <- drag
        , let as' = as { dragOn = Nothing }
        -> ( as', [ (PreviewInstance new, Remove) | Just new <- pure $ newDNA as ] )

    EndDrag
        | Just _ <- drag
        , Just new <- newDNA as
        , new `notElem` M.elems dnas
        , let newKey = succ (fst (M.findMax dnas))
        , let dnas' = M.insert newKey new dnas
        , let as' = as { drag = Nothing, dnas = dnas' }
        -> ( as'
           , [ (PreviewInstance new, Remove)
             , (MainInstance new, SummonAt MainPos)
             ] ++
             moveAllSmall as'
           )

        | Just d <- drag
        , Just new <- newDNA as
        , Just i <- elemIndex new (M.elems dnas)
        -> ( as { drag = Nothing }
           , [ (PreviewInstance new, FadeOut (SmallPos (length dnas) i))
             , moveOneSmall as d ] )

        | Just d <- drag
        -> ( as { drag = Nothing }, [ moveOneSmall as d ] )

    CancelDrag
        | Just d <- drag
        -> ( as { drag = Nothing }
           , [ (PreviewInstance new, Remove) | Just new <- pure $ newDNA as ] ++
             [ moveOneSmall as d ] )

    Delete
        | S2.OneSelected k <- sel
        , Just i <- M.lookupIndex k dnas
        , let d = as `dnaAtKey` k
        , let as' = as { sel = S2.empty, dnas = M.delete k dnas }
        -> ( as'
           , [ (PreviewInstance d, Remove)
             , (MainInstance d, FadeOut (DeletedPos (length dnas) i))
             ] ++
             moveAllSmall as'
           )
    _ -> (as, [])

