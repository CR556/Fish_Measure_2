import type { FishMeasurementEvent, SubjectEvent } from '../../modules/fish-measure';
import { createExternalStore } from './externalStore';

export const subjectStore = createExternalStore<SubjectEvent | null>(null);
export const measurementStore = createExternalStore<FishMeasurementEvent | null>(null);

export function receiveSubject(event: SubjectEvent) {
  if ((subjectStore.getSnapshot()?.frameId ?? -1) <= event.frameId) subjectStore.set(event);
}

export function receiveMeasurement(event: FishMeasurementEvent) {
  if ((measurementStore.getSnapshot()?.frameId ?? -1) <= event.frameId) measurementStore.set(event);
}

export function clearMeasurementStores() {
  subjectStore.set(null);
  measurementStore.set(null);
}
