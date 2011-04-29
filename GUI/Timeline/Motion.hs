{-# LANGUAGE NamedFieldPuns #-}
module GUI.Timeline.Motion (
    zoomIn, zoomOut, zoomToFit,
    scrollLeft, scrollRight, scrollToBeginning, scrollToEnd, centreOnCursor,
    vscrollDown, vscrollUp,
    queueRedrawTimelines
  ) where

import GUI.Timeline.Types
import GUI.Timeline.Render.Constants
import GUI.State (HECs(..))

import Graphics.UI.Gtk

import Data.IORef
import Control.Monad
-- import Text.Printf
-- import Debug.Trace

-------------------------------------------------------------------------------
-- Zoom in works by expanding the current view such that the
-- left hand edge of the original view remains at the same
-- position and the zoom in factor is 2.
-- For example, zoom into the time range 1.0 3.0
-- produces a new view with the time range 1.0 2.0

zoomIn :: TimelineWindow -> IO ()
zoomIn  = zoom (/2)

zoomOut :: TimelineWindow -> IO ()
zoomOut  = zoom (*2)

zoom :: (Double->Double) -> TimelineWindow -> IO ()
zoom factor state@TimelineWindow{timelineAdj, scaleIORef, cursorIORef} = do
       scaleValue <- readIORef scaleIORef
       let clampedFactor = if factor scaleValue < 1 then
                             id
                           else
                             factor
       let newScaleValue = clampedFactor scaleValue
       writeIORef scaleIORef newScaleValue

       cursor <- readIORef cursorIORef
       hadj_value <- adjustmentGetValue timelineAdj
       hadj_pagesize <- adjustmentGetPageSize timelineAdj -- Get size of bar

       let newPageSize = clampedFactor hadj_pagesize
       adjustmentSetPageSize timelineAdj newPageSize

       let cursord = fromIntegral cursor
       when (cursord >= hadj_value && cursord < hadj_value + hadj_pagesize) $
         adjustmentSetValue timelineAdj $
             cursord - clampedFactor (cursord - hadj_value)

       let pageshift = 0.9 * newPageSize
       let nudge     = 0.1 * newPageSize

       adjustmentSetStepIncrement timelineAdj nudge
       adjustmentSetPageIncrement timelineAdj pageshift

       queueRedrawTimelines state

-------------------------------------------------------------------------------

zoomToFit :: TimelineWindow -> IO ()
zoomToFit state@TimelineWindow{hecsIORef, scaleIORef, timelineAdj, timelineDrawingArea} = do
  mb_hecs <- readIORef hecsIORef
  case mb_hecs of
    Nothing   -> writeIORef scaleIORef (-1.0)
    Just hecs -> do
       let lastTx = hecLastEventTime hecs
       (w, _) <- widgetGetSize timelineDrawingArea
       let newScaleValue = fromIntegral lastTx / fromIntegral (w - 2*ox)
                           -- leave a gap of ox pixels at each end
       writeIORef scaleIORef newScaleValue

       -- Configure the horizontal scrollbar units to correspond to ns.
       -- leave a gap of ox pixels on the left and right of the full trace
       let gap   = fromIntegral ox * newScaleValue
           lower = -gap
           upper = fromIntegral lastTx + gap
           page  = upper + gap

       adjustmentSetLower    timelineAdj lower
       adjustmentSetValue    timelineAdj lower
       adjustmentSetUpper    timelineAdj upper
       adjustmentSetPageSize timelineAdj page
       -- TODO: this seems suspicious:
       adjustmentSetStepIncrement timelineAdj 0
       adjustmentSetPageIncrement timelineAdj 0

       queueRedrawTimelines state

-------------------------------------------------------------------------------

scrollLeft, scrollRight, scrollToBeginning, scrollToEnd, centreOnCursor
  :: TimelineWindow -> IO ()

scrollLeft        = scroll (\val page l u -> l `max` (val - page/2))
scrollRight       = scroll (\val page l u -> (u - page) `min` (val + page/2))
scrollToBeginning = scroll (\_ _ l u -> l)
scrollToEnd       = scroll (\_ _ l u -> u)

centreOnCursor state@TimelineWindow{cursorIORef} = do
  cursor <- readIORef cursorIORef
  scroll (\_ page l u -> max l (fromIntegral cursor - page/2)) state

scroll :: (Double -> Double -> Double -> Double -> Double)
       -> TimelineWindow -> IO ()
scroll adjust TimelineWindow{timelineAdj}
  = do hadj_value <- adjustmentGetValue timelineAdj
       hadj_pagesize <- adjustmentGetPageSize timelineAdj
       hadj_lower <- adjustmentGetLower timelineAdj
       hadj_upper <- adjustmentGetUpper timelineAdj
       let newValue = adjust hadj_value hadj_pagesize hadj_lower hadj_upper
           newValue' = max hadj_lower (min (hadj_upper - hadj_pagesize) newValue)
       adjustmentSetValue timelineAdj newValue'
       adjustmentValueChanged timelineAdj

vscrollDown, vscrollUp :: TimelineWindow -> IO ()
vscrollDown = vscroll (\val page l u -> (u - page) `min` (val + page/8))
vscrollUp   = vscroll (\val page l u -> l `max` (val - page/8))

vscroll :: (Double -> Double -> Double -> Double -> Double)
        -> TimelineWindow -> IO ()
vscroll adjust TimelineWindow{timelineVAdj}
  = do hadj_value <- adjustmentGetValue timelineVAdj
       hadj_pagesize <- adjustmentGetPageSize timelineVAdj
       hadj_lower <- adjustmentGetLower timelineVAdj
       hadj_upper <- adjustmentGetUpper timelineVAdj
       let newValue = adjust hadj_value hadj_pagesize hadj_lower hadj_upper
       adjustmentSetValue timelineVAdj newValue
       adjustmentValueChanged timelineVAdj

-- -----------------------------------------------------------------------------

queueRedrawTimelines :: TimelineWindow -> IO ()
queueRedrawTimelines state = do
  widgetQueueDraw (timelineDrawingArea state)
  widgetQueueDraw (timelineLabelDrawingArea state)
