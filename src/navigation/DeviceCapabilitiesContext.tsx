import React, { createContext, useContext } from 'react';

type DeviceCapabilities = { lidarSupported: boolean };

const Context = createContext<DeviceCapabilities>({ lidarSupported: false });

export function DeviceCapabilitiesProvider({
  lidarSupported,
  children,
}: DeviceCapabilities & { children: React.ReactNode }) {
  return <Context.Provider value={{ lidarSupported }}>{children}</Context.Provider>;
}

export function useDeviceCapabilities() {
  return useContext(Context);
}
