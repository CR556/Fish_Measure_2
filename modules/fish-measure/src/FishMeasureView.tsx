import { requireNativeView } from 'expo';
import * as React from 'react';

import type { FishMeasureViewProps, FishMeasureViewRef } from './FishMeasure.types';

const NativeView = requireNativeView<
  FishMeasureViewProps & { ref?: React.Ref<FishMeasureViewRef> }
>('FishMeasure');

export const FishMeasureView = React.forwardRef<FishMeasureViewRef, FishMeasureViewProps>(
  function FishMeasureView(props, ref) {
    return <NativeView {...props} ref={ref} />;
  }
);
