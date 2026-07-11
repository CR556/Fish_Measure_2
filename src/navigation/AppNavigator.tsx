import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import React from 'react';
import { Text } from 'react-native';

import { CatchDetailScreen } from '../screens/CatchDetailScreen';
import { CaptureReviewScreen } from '../screens/CaptureReviewScreen';
import { LogScreen } from '../screens/LogScreen';
import { MapScreen } from '../screens/MapScreen';
import { MeasureScreen } from '../screens/MeasureScreen';
import { SettingsScreen } from '../screens/SettingsScreen';
import { SpeciesPickerScreen } from '../screens/SpeciesPickerScreen';
import { colors } from '../lib/colors';
import type { RootStackParamList, TabParamList } from './types';

const Root = createNativeStackNavigator<RootStackParamList>();
const Tabs = createBottomTabNavigator<TabParamList>();

const tabGlyphs: Record<keyof TabParamList, string> = {
  Measure: '◎',
  Log: '≡',
  Map: '⌖',
  Settings: '⚙',
};

function MainTabs() {
  return (
    <Tabs.Navigator
      screenOptions={({ route }) => ({
        headerShown: false,
        tabBarActiveTintColor: colors.aqua,
        tabBarInactiveTintColor: colors.textMuted,
        tabBarStyle: { backgroundColor: colors.panel, borderTopColor: colors.border },
        tabBarIcon: ({ color }) => (
          <Text style={{ color, fontSize: 22 }}>{tabGlyphs[route.name]}</Text>
        ),
      })}
    >
      <Tabs.Screen name="Measure" component={MeasureScreen} />
      <Tabs.Screen name="Log" component={LogScreen} />
      <Tabs.Screen name="Map" component={MapScreen} />
      <Tabs.Screen name="Settings" component={SettingsScreen} />
    </Tabs.Navigator>
  );
}

export function AppNavigator() {
  return (
    <Root.Navigator screenOptions={{ headerStyle: { backgroundColor: colors.panel } }}>
      <Root.Screen name="Tabs" component={MainTabs} options={{ headerShown: false }} />
      <Root.Screen
        name="CaptureReview"
        component={CaptureReviewScreen}
        options={{ presentation: 'modal', title: 'Review Catch' }}
      />
      <Root.Screen name="CatchDetail" component={CatchDetailScreen} options={{ title: 'Catch' }} />
      <Root.Screen
        name="SpeciesPicker"
        component={SpeciesPickerScreen}
        options={{ presentation: 'modal', title: 'Choose Species' }}
      />
    </Root.Navigator>
  );
}
