import { Directory, File, Paths } from 'expo-file-system';

const root = new Directory(Paths.document, 'catches');
const stagingRoot = new Directory(root, '.staging');

export function initializeCatchStorage() {
  root.create({ intermediates: true, idempotent: true });
  stagingRoot.create({ intermediates: true, idempotent: true });
}

export function createCaptureStagingDirectory(catchId: string) {
  initializeCatchStorage();
  const directory = new Directory(stagingRoot, catchId);
  directory.create({ intermediates: true, idempotent: true });
  return directory;
}

export async function commitCaptureDirectory(catchId: string) {
  const staging = new Directory(stagingRoot, catchId);
  if (!staging.exists) throw new Error(`Missing capture staging directory for ${catchId}.`);
  const destination = new Directory(root, catchId);
  if (destination.exists) throw new Error(`Catch directory ${catchId} already exists.`);
  await staging.move(destination);
  return destination;
}

export function discardCaptureDirectory(catchId: string) {
  const staging = new Directory(stagingRoot, catchId);
  if (staging.exists) staging.delete();
}

export function deleteCatchDirectory(catchId: string) {
  const directory = new Directory(root, catchId);
  if (directory.exists) directory.delete();
}

export function cleanupAbandonedStagingDirectories() {
  initializeCatchStorage();
  for (const entry of stagingRoot.list()) {
    if (entry instanceof Directory) entry.delete();
  }
}

export function relativeCatchPath(catchId: string, name: string) {
  return `catches/${catchId}/${name}`;
}

export function resolveCatchFile(relativePath: string) {
  return new File(Paths.document, relativePath);
}
