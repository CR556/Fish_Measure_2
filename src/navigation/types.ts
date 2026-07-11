export type RootStackParamList = {
  Tabs: undefined;
  CaptureReview: { draftId: string };
  CatchDetail: { catchId: string };
  SpeciesPicker: { catchId?: string } | undefined;
};

export type TabParamList = {
  Measure: undefined;
  Log: undefined;
  Map: undefined;
  Settings: undefined;
};
