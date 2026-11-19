Pod::Spec.new do |s|
  s.name             = 'omnitrain_watch_link'
  s.version          = '0.1.0'
  s.summary          = 'OmniTrain phone-side WatchConnectivity link.'
  s.description      = 'Queues, buffers, acknowledges and reports reachability for the OmniTrain watch link.'
  s.homepage         = 'https://omnitrain.invalid'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'OmniTrain' => 'dev@omnitrain.invalid' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.0'
end
