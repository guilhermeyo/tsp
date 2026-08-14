Pod::Spec.new do |s|
  s.name           = 'LauncherNative'
  s.version        = '1.0.0'
  s.summary        = 'App Group config storage, widget reload and font-design resolution.'
  s.description    = 'Local Expo module backing the Simple Phone launcher: reads and writes the shared launcher_config JSON, reloads WidgetKit timelines, and resolves SwiftUI font designs to concrete families.'
  s.license        = 'MIT'
  s.author         = 'Guilherme Yamakawa de Oliveira'
  s.homepage       = 'https://github.com/guilhermeyo/tsp'
  # Matches the app's deploymentTarget in app.json (expo-build-properties).
  s.platforms      = { :ios => '17.0' }
  s.swift_version  = '5.9'
  s.source         = { git: '' }
  # Expo modules are compiled into the app's own binary rather than shipped as
  # dynamic frameworks; this is what every expo-module podspec does.
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  # Swift `import` already emits autolink hints for SDK frameworks, but naming
  # them keeps the dependency legible to anyone reading the podspec.
  s.frameworks     = 'WidgetKit', 'UIKit'

  s.source_files   = 'LauncherNativeModule.swift'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_COMPILATION_MODE' => 'wholemodule'
  }
end
