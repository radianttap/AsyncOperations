
Pod::Spec.new do |s|
  s.name             = "AsyncOperations"
  s.version          = "0.1.0"
  s.summary          = "A toolbox of NSOperation subclasses for a variety of asynchronous programming needs."
  s.description      = "A toolbox of NSOperation subclasses for a variety of asynchronous programming needs. I'm adding additional words here to satisy CocoaPods' pedantry."
  s.homepage         = "https://github.com/jaredsinclair/AsyncOperations"
  s.license          = 'MIT'
  s.author           = { "Jared Sinclair" => "desk@jaredsinclair.com" }
  s.source           = { :git => "https://github.com/jaredsinclair/AsyncOperations.git", :tag => s.version.to_s }

  s.platform     = :ios, '8.0'
  s.requires_arc = true

  s.frameworks = 'Foundation'
  s.source_files = 'Source/*.swift'
end
