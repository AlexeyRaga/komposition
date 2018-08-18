{-# OPTIONS_GHC -fno-warn-unticked-promoted-constructors #-}

{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE ConstraintKinds    #-}
{-# LANGUAGE DataKinds          #-}
{-# LANGUAGE FlexibleContexts   #-}
{-# LANGUAGE GADTs              #-}
{-# LANGUAGE KindSignatures     #-}
{-# LANGUAGE RankNTypes         #-}
{-# LANGUAGE TypeFamilies       #-}
{-# LANGUAGE TypeInType         #-}
{-# LANGUAGE TypeOperators      #-}
{-# LANGUAGE LambdaCase         #-}
{-# LANGUAGE OverloadedStrings  #-}

module FastCut.UserInterface where

import           FastCut.Prelude                   hiding ( State )

import           Motor.FSM                         hiding ( Delete )
import           Data.Row.Records
import           Pipes

import           FastCut.Focus
import           FastCut.KeyMap
import           FastCut.Library
import           FastCut.Composition.Insert
import           FastCut.Project
import           FastCut.Progress

data Mode
  = TimelineMode
  | LibraryMode
  | ImportMode

data SMode m where
  STimelineMode :: SMode TimelineMode
  SLibraryMode :: SMode LibraryMode
  SImportMode :: SMode ImportMode

modeTitle :: SMode m -> Text
modeTitle = \case
  STimelineMode -> "Timeline Mode"
  SLibraryMode  -> "Library Mode"
  SImportMode   -> "Import Mode"

class ReturnsToTimeline (mode :: Mode)

instance ReturnsToTimeline LibraryMode
instance ReturnsToTimeline ImportMode

data InsertType
  = InsertComposition
  | InsertClip
  | InsertGap
  deriving (Show, Eq, Ord)

data Command mode where
  Cancel :: Command mode
  Help :: Command mode

  FocusCommand :: FocusCommand -> Command TimelineMode
  InsertCommand :: InsertType -> InsertPosition -> Command TimelineMode
  Delete :: Command TimelineMode
  Import :: Command TimelineMode
  Render :: Command TimelineMode
  Exit :: Command TimelineMode

  LibraryUp :: Command LibraryMode
  LibraryDown :: Command LibraryMode
  LibrarySelect :: Command LibraryMode

deriving instance Eq (Command mode)

deriving instance Ord (Command mode)

commandName :: Command mode -> Text
commandName = \case
  Cancel           -> "Cancel"
  Help             -> "Show Help"
  FocusCommand cmd ->
    case cmd of
      FocusUp -> "Move Focus Up"
      FocusDown -> "Move Focus Down"
      FocusLeft -> "Move Focus Left"
      FocusRight -> "Move Focus Right"
  InsertCommand insertType insertPosition ->
    mconcat [insertTypeName insertType, " (", insertPositionName insertPosition, ")"]
  Delete           -> "Delete"
  Import           -> "Import Assets"
  Render           -> "Render"
  Exit             -> "Exit"

  LibraryUp        -> "Navigate Up"
  LibraryDown      -> "Navigate Down"
  LibrarySelect    -> "Select Asset"
  where
    insertTypeName :: InsertType -> Text
    insertTypeName = \case
      InsertClip -> "Insert Clip"
      InsertGap -> "Insert Gap"
      InsertComposition -> "Insert Composition"
    insertPositionName :: InsertPosition -> Text
    insertPositionName = \case
      LeftMost -> "Leftmost"
      LeftOf -> "Left of"
      RightOf -> "Right of"
      RightMost -> "Rightmost"

data Event mode where
  CommandKeyMappedEvent :: Command mode -> Event mode

  ImportFileSelected :: FilePath -> Event ImportMode
  ImportAutoSplitSet :: Bool -> Event ImportMode
  ImportClicked :: Event ImportMode

data ModeKeyMap where
  ModeKeyMap :: forall mode. Ord (Command mode) => SMode mode -> KeyMap (Command mode) -> ModeKeyMap

type KeyMaps = forall mode. SMode mode -> KeyMap (Event mode)

class Enum c => DialogChoice c where
  toButtonLabel :: c -> Text

data FileChooserMode
  = Open
  | Save

data PromptMode ret where
  NumberPrompt :: (Double, Double) -> PromptMode Double
  TextPrompt :: PromptMode Text

class MonadFSM m =>
      UserInterface m where
  type State m :: Mode -> Type
  start ::
       Name n
    -> KeyMaps
    -> Project
    -> Focus ft
    -> Actions m '[ n !+ State m TimelineMode] r ()
  updateTimeline
    :: Name n
    -> Project
    -> Focus ft
    -> Actions m '[ n := State m TimelineMode !--> State m TimelineMode] r ()
  returnToTimeline
    :: ReturnsToTimeline mode
    => Name n
    -> Project
    -> Focus ft
    -> Actions m '[ n := State m mode !--> State m TimelineMode] r ()
  enterLibrary
    :: Name n
    -> [Asset mt]
    -> Int
    -> Actions m '[ n := State m TimelineMode !--> State m LibraryMode] r ()
  updateLibrary
    :: Name n
    -> [Asset mt]
    -> Int
    -> Actions m '[ n := State m LibraryMode !--> State m LibraryMode] r ()
  enterImport
    :: Name n
    -> Actions m '[ n := State m TimelineMode !--> State m ImportMode] r ()
  nextEvent
    :: Name n
    -> Actions m '[ n := Remain (State m t)] r (Event t)
  beep :: Name n -> Actions m '[] r ()
  dialog
    :: DialogChoice c
    => Name n
    -> Text -- ^ Dialog window title.
    -> Text -- ^ Dialog message.
    -> [c] -- ^ Choices of the dialog, rendered as buttons.
    -> Actions m '[ n := Remain (State m t)] r (Maybe c)
  prompt
    :: Name n
    -> Text -- ^ Prompt window title.
    -> Text -- ^ Prompt message.
    -> Text -- ^ Button text for confirming the choice.
    -> PromptMode ret -- ^ Type of prompt, decides the return value type.
    -> Actions m '[ n := Remain (State m t)] r (Maybe ret)
  chooseFile
    :: Name n
    -> FileChooserMode
    -> Text -- ^ Dialog window title.
    -> FilePath
    -> Actions m '[ n := Remain (State m t)] r (Maybe FilePath)
  progressBar
    :: Name n
    -> Text -- ^ Progress window title.
    -> Producer ProgressUpdate IO a -- ^ Progress updates producer.
    -> Actions m '[ n := Remain (State m t)] r (Maybe a)
  help
    :: Name n
    -> [ModeKeyMap]
    -> Actions m '[ n := Remain (State m t)] r ()
  exit :: Name n -> Actions m '[ n !- State m s] r ()

-- | Convenient type for actions that transition from one mode (of
-- type 'mode1') into another mode (of type 'mode2'), doing some user
-- interactions, and returning back to the first mode with a value of
-- type 'a'.
type ThroughMode mode1 mode2 m n a
   = forall i o state2 state1.
   ( UserInterface m
     , HasType n state1 i
     , HasType n state1 o
     , (Modify n state2 i .! n) ~ state2
     , Modify n state1 (Modify n state2 i) ~ o
     , Modify n state2 (Modify n state2 i) ~ Modify n state2 i
     , state1 ~ State m mode1
     , state2 ~ State m mode2
     )
   => m i o a
