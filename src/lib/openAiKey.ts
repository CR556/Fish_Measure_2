import * as SecureStore from 'expo-secure-store';

const KEY_NAME = 'fish-measure-2:openai-api-key';

export function getOpenAiApiKey() {
  return SecureStore.getItemAsync(KEY_NAME);
}

export function setOpenAiApiKey(value: string) {
  const trimmed = value.trim();
  return trimmed
    ? SecureStore.setItemAsync(KEY_NAME, trimmed, {
        keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
      })
    : SecureStore.deleteItemAsync(KEY_NAME);
}

export function deleteOpenAiApiKey() {
  return SecureStore.deleteItemAsync(KEY_NAME);
}
