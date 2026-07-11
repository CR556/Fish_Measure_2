import AsyncStorage from '@react-native-async-storage/async-storage';
import { useCallback, useEffect, useState } from 'react';

const SETTINGS_KEY = 'fish-measure-2:settings:v1';

export type Settings = {
  units: 'imperial' | 'metric';
  locationEnabled: boolean;
  saveToPhotosOnKeep: boolean;
  openAiIdentificationEnabled: boolean;
  openAiAccuracy: 'standard' | 'higher';
};

export const defaultSettings: Settings = {
  units: 'imperial',
  locationEnabled: true,
  saveToPhotosOnKeep: false,
  openAiIdentificationEnabled: false,
  openAiAccuracy: 'standard',
};

export function useSettings() {
  const [settings, setSettingsState] = useState(defaultSettings);
  const [loaded, setLoaded] = useState(false);
  useEffect(() => {
    AsyncStorage.getItem(SETTINGS_KEY)
      .then((stored) => {
        if (stored) setSettingsState({ ...defaultSettings, ...JSON.parse(stored) });
      })
      .finally(() => setLoaded(true));
  }, []);
  const setSettings = useCallback((next: Settings | ((current: Settings) => Settings)) => {
    setSettingsState((current) => {
      const resolved = typeof next === 'function' ? next(current) : next;
      void AsyncStorage.setItem(SETTINGS_KEY, JSON.stringify(resolved));
      return resolved;
    });
  }, []);
  return { settings, setSettings, loaded };
}
