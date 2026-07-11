import FishMeasureModule from './src/FishMeasureModule';

export { FishMeasureView } from './src/FishMeasureView';
export * from './src/FishMeasure.types';

export function isLidarSupported(): boolean {
  return FishMeasureModule.isLidarSupported();
}

export function saveImageToPhotos(
  path: string,
  userComment: string,
  imageDescription: string,
  gps?: { lat: number; lon: number }
): Promise<void> {
  return FishMeasureModule.saveImageToPhotos(path, userComment, imageDescription, gps);
}
