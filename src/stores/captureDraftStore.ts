import type { AutoCapturePayload, ManualCapturePayload } from '../../modules/fish-measure';

export type CaptureDraft = {
  id: string;
  outputDirectoryUri: string;
  mode: 'auto' | 'manual';
  payload: AutoCapturePayload | ManualCapturePayload;
};

const drafts = new Map<string, CaptureDraft>();

export function putCaptureDraft(draft: CaptureDraft) {
  drafts.set(draft.id, draft);
}

export function getCaptureDraft(id: string) {
  return drafts.get(id) ?? null;
}

export function removeCaptureDraft(id: string) {
  const draft = drafts.get(id) ?? null;
  drafts.delete(id);
  return draft;
}
