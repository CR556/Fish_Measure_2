import type { ProjectedPoint } from '../../modules/fish-measure';

/**
 * Tiny external store for the 30 Hz projection stream. Only components that
 * subscribe (the shapes overlay) re-render per frame — routing this through
 * screen-level state re-rendered the whole UI tree every tick, which is what
 * made the app crawl once ~10 points existed.
 */
type Listener = () => void;

let snapshot: Record<string, ProjectedPoint> = {};
const listeners = new Set<Listener>();

export const projectionStore = {
  set(points: ProjectedPoint[]) {
    const next: Record<string, ProjectedPoint> = {};
    for (const p of points) {
      next[p.id] = p;
    }
    snapshot = next;
    listeners.forEach((l) => l());
  },
  clear() {
    snapshot = {};
    listeners.forEach((l) => l());
  },
  get: (): Record<string, ProjectedPoint> => snapshot,
  subscribe(listener: Listener): () => void {
    listeners.add(listener);
    return () => {
      listeners.delete(listener);
    };
  },
};
