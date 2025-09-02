import { Image } from 'react-native';

export class AudioAssetResolver {
  static resolve(uri: string | number): string {
    // Handle numeric asset IDs from require('./file.mp3')
    if (typeof uri === 'number') {
      const asset = Image.resolveAssetSource(uri);
      return asset?.uri ?? '';
    }

    if (typeof uri !== 'string') {
      return '';
    }

    if (
      uri.startsWith('http://') ||
      uri.startsWith('https://') ||
      uri.startsWith('file://') ||
      uri.startsWith('content://') ||
      uri.startsWith('asset://')
    ) {
      return uri;
    }

    // Assume it's a local asset path
    return this.resolveAsset(uri);
  }

  static resolveAsset(assetPath: string): string {
    const cleanPath = assetPath.startsWith('/')
      ? assetPath.slice(1)
      : assetPath;
    return `asset://${cleanPath}`; // Same for both iOS + Android
  }

  static isLocalAsset(uri: string): boolean {
    return (
      uri.startsWith('asset://') ||
      (!uri.startsWith('http://') &&
        !uri.startsWith('https://') &&
        !uri.startsWith('file://') &&
        !uri.startsWith('content://'))
    );
  }
}

export const resolveAudioAsset = (assetPath: string | number): string => {
  return AudioAssetResolver.resolve(assetPath);
};
