import {
  Canvas,
  Circle,
  Path,
  Skia,
  usePathInterpolation,
} from '@shopify/react-native-skia';
import React, { useEffect, useMemo, useRef } from 'react';
import { StyleSheet, useWindowDimensions } from 'react-native';
import { useSharedValue, withTiming } from 'react-native-reanimated';

import type {
  FishMeasurementEvent,
  SubjectEvent,
  ViewPoint,
} from '../../../modules/fish-measure/src/FishMeasure.types';
import { colors } from '../../lib/colors';

type Props = {
  subject: SubjectEvent | null;
  measurement: FishMeasurementEvent | null;
  manualPoints?: ViewPoint[];
};

function pointsFromFlat(values: number[]) {
  const points: ViewPoint[] = [];
  for (let index = 0; index + 1 < values.length; index += 2) {
    points.push({ x: values[index], y: values[index + 1] });
  }
  return points;
}

function buildPath(points: ViewPoint[], close: boolean) {
  const builder = Skia.PathBuilder.Make();
  if (points.length > 0) {
    builder.moveTo(points[0].x, points[0].y);
    for (const point of points.slice(1)) builder.lineTo(point.x, point.y);
    if (close) builder.close();
  }
  return builder.build();
}

function ghostPoints(count: number, width: number, height: number) {
  const total = Math.max(4, count);
  const centerX = width * 0.5;
  const centerY = height * 0.43;
  const halfWidth = width * 0.37;
  const halfHeight = Math.min(height * 0.105, width * 0.16);
  const points: ViewPoint[] = [];
  for (let index = 0; index < total; index += 1) {
    const angle = (index / total) * Math.PI * 2;
    const noseTailTaper = 0.42 + 0.58 * Math.abs(Math.sin(angle));
    const tailNotch = Math.cos(angle) < -0.84 ? 0.72 : 1;
    points.push({
      x: centerX + Math.cos(angle) * halfWidth * tailNotch,
      y: centerY + Math.sin(angle) * halfHeight * noseTailTaper,
    });
  }
  return points;
}

export function MeasurementOverlay({ subject, measurement, manualPoints = [] }: Props) {
  const { width, height } = useWindowDimensions();
  const livePoints = useMemo(() => pointsFromFlat(subject?.contour ?? []), [subject?.contour]);
  const pointCount = Math.max(4, livePoints.length);
  const ghost = useMemo(() => ghostPoints(pointCount, width, height), [height, pointCount, width]);
  const target = livePoints.length >= 4 ? livePoints : ghost;
  const ghostPath = useMemo(() => buildPath(ghost, true), [ghost]);
  const targetPath = useMemo(() => buildPath(target, true), [target]);
  const centerlinePath = useMemo(
    () => buildPath(pointsFromFlat(measurement?.centerline ?? []), false),
    [measurement?.centerline]
  );
  const manualPath = useMemo(() => buildPath(manualPoints, false), [manualPoints]);
  const morph = useSharedValue(0);
  const previousState = useRef(subject?.state ?? 'none');

  useEffect(() => {
    if (subject?.state === 'locked' && previousState.current !== 'locked') {
      morph.value = 0;
      morph.value = withTiming(1, { duration: 360 });
    } else if (subject?.state !== 'locked') {
      morph.value = withTiming(0, { duration: 180 });
    }
    previousState.current = subject?.state ?? 'none';
  }, [morph, subject?.state]);

  const morphedPath = usePathInterpolation(morph, [0, 1], [ghostPath, targetPath]);
  const contourColor = subject?.state === 'locked' ? colors.keep : colors.aqua;

  return (
    <Canvas pointerEvents="none" style={StyleSheet.absoluteFill}>
      <Path
        path={morphedPath}
        color={contourColor}
        style="stroke"
        strokeWidth={subject?.state === 'locked' ? 4 : 2}
        opacity={subject?.state === 'none' ? 0.45 : 0.9}
      />
      {measurement?.centerline && measurement.centerline.length >= 4 ? (
        <Path path={centerlinePath} color={colors.amber} style="stroke" strokeWidth={3} />
      ) : null}
      {measurement ? (
        <>
          <Circle cx={measurement.nose.x} cy={measurement.nose.y} r={7} color={colors.keep} />
          <Circle cx={measurement.tail.x} cy={measurement.tail.y} r={7} color={colors.amber} />
        </>
      ) : null}
      {manualPoints.length >= 2 ? (
        <Path path={manualPath} color={colors.amber} style="stroke" strokeWidth={4} />
      ) : null}
      {manualPoints.map((point, index) => (
        <Circle key={`${index}-${point.x}-${point.y}`} cx={point.x} cy={point.y} r={7} color={colors.amber} />
      ))}
    </Canvas>
  );
}
