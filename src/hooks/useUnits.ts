import AsyncStorage from '@react-native-async-storage/async-storage';
import { useCallback, useEffect, useState } from 'react';

import { nextUnit, Unit, UNITS } from '../lib/units';

const STORAGE_KEY = 'lidar-distance.unit';

export function useUnits() {
  const [unit, setUnit] = useState<Unit>('m');

  useEffect(() => {
    AsyncStorage.getItem(STORAGE_KEY)
      .then((stored) => {
        if (stored && UNITS.includes(stored as Unit)) {
          setUnit(stored as Unit);
        }
      })
      .catch(() => {});
  }, []);

  const cycleUnit = useCallback(() => {
    setUnit((current) => {
      const next = nextUnit(current);
      AsyncStorage.setItem(STORAGE_KEY, next).catch(() => {});
      return next;
    });
  }, []);

  return { unit, cycleUnit };
}
