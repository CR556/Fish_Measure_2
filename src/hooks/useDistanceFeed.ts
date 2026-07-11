import { useCallback, useEffect, useRef, useState } from 'react';

import type { DistanceEvent } from '../../modules/fish-measure';

const STALE_AFTER_MS = 500;
/** Native events arrive at updateHz (30); re-rendering the readout above
 * ~10 Hz is wasted work, so state updates are throttled. */
const MIN_RENDER_INTERVAL_MS = 100;

/**
 * Holds the latest distance event and flags the readout as stale when no
 * event has arrived recently (lost surface, tracking dropout, mode switch).
 */
export function useDistanceFeed() {
  const [event, setEvent] = useState<DistanceEvent | null>(null);
  const [stale, setStale] = useState(true);
  const lastReceivedAt = useRef(0);
  const lastRenderedAt = useRef(0);

  const onDistance = useCallback((e: { nativeEvent: DistanceEvent }) => {
    const now = Date.now();
    lastReceivedAt.current = now;
    if (now - lastRenderedAt.current < MIN_RENDER_INTERVAL_MS) return;
    lastRenderedAt.current = now;
    setEvent(e.nativeEvent);
    setStale(false);
  }, []);

  useEffect(() => {
    const interval = setInterval(() => {
      if (Date.now() - lastReceivedAt.current > STALE_AFTER_MS) {
        setStale(true);
      }
    }, 250);
    return () => clearInterval(interval);
  }, []);

  const reset = useCallback(() => {
    setEvent(null);
    setStale(true);
  }, []);

  return { event, stale, onDistance, reset };
}
