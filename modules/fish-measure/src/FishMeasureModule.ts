import { NativeModule, requireNativeModule } from 'expo';

declare class FishMeasureNativeModule extends NativeModule {
  isLidarSupported(): boolean;
  /**
   * Embeds EXIF UserComment + TIFF ImageDescription into the image at `path`
   * and saves it to the camera roll (prompts for add-only permission).
   */
  saveImageToPhotos(
    path: string,
    userComment: string,
    imageDescription: string,
    gps?: { lat: number; lon: number }
  ): Promise<void>;
}

export default requireNativeModule<FishMeasureNativeModule>('FishMeasure');
