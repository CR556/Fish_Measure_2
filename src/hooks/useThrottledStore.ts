import { useEffect, useState } from 'react';

type Store<T> = {
  getSnapshot(): T;
  subscribe(listener: () => void): () => void;
};

export function useThrottledStore<T>(store: Store<T>, intervalMs = 100) {
  const [value, setValue] = useState(store.getSnapshot);
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | null = null;
    let lastRenderedAt = 0;
    const publish = () => {
      lastRenderedAt = Date.now();
      timer = null;
      setValue(store.getSnapshot());
    };
    return store.subscribe(() => {
      const remaining = intervalMs - (Date.now() - lastRenderedAt);
      if (remaining <= 0) publish();
      else if (timer == null) timer = setTimeout(publish, remaining);
    });
  }, [intervalMs, store]);
  return value;
}
