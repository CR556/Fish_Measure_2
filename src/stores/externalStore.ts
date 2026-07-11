import { useSyncExternalStore } from 'react';

export function createExternalStore<T>(initial: T) {
  let value = initial;
  const listeners = new Set<() => void>();
  return {
    getSnapshot: () => value,
    subscribe(listener: () => void) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    set(next: T) {
      value = next;
      listeners.forEach((listener) => listener());
    },
    update(updater: (current: T) => T) {
      value = updater(value);
      listeners.forEach((listener) => listener());
    },
  };
}

export function useExternalStore<T>(store: ReturnType<typeof createExternalStore<T>>) {
  return useSyncExternalStore(store.subscribe, store.getSnapshot, store.getSnapshot);
}
