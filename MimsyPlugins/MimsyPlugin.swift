import Cocoa

/// This is the base class that plugins inherit from. Often only onLoad
/// is overriden.
public class MimsyPlugin: NSObject {
    /// Mimsy will instantiate plugins when it loads their bundles.
    public init(fromApp app: MimsyApp, bundle: NSBundle)
    {
        self.app = app
        self.bundle = bundle
    }
    
    /// Called by Mimsy after the plugin is instantiated. Note that
    /// this is called multiple times with increasing stage numbers:
    /// * Stage 0 is called as plugins load. Plugins seldom use this.
    /// * Stage 1 is normally used by the built-in plugins to initialize themselves.
    /// * Stage 2 is normally used by custom plugins to initialize themselves.
    /// * Stage 3 can be used by plugins that want to execute after other plugins have initialized.
    ///
    /// - Returns: nil if the plugin was able to load or an error message if it
    /// failed to load (or doesn't want to run).
    public func onLoad(stage: Int) -> String?
    {
        return nil
    }
    
    /// Called just before Mimsy exits (assuming it exits normally).
    public func onUnload()
    {
    }
    
    /// Called between stage 0 and stage 1 and when the user edits the plugin's settings file.
    public func onLoadSettings(settings: MimsySettings)
    {
    }
    
    /// Plugins should use MimsyApp whenever they want to communicate with
    /// Mimsy.
    public let app: MimsyApp
    
    /// The plugin's bundle.
    public let bundle: NSBundle
}

