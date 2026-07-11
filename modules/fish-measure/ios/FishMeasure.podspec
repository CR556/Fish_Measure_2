Pod::Spec.new do |s|
  s.name           = 'FishMeasure'
  s.version        = '1.0.0'
  s.summary        = 'Native ARKit and LiDAR measurement for Fish Measure 2'
  s.description    = 'Segments fish, lifts centerlines through LiDAR depth, and captures measurement evidence.'
  s.author         = ''
  s.homepage       = 'https://docs.expo.dev/modules/'
  s.platforms      = {
    :ios => '17.0'
  }
  s.source         = { git: '' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  # Swift/Objective-C compatibility
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }

  s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"
end
