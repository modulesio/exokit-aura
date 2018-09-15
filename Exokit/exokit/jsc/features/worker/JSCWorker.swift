import Foundation
import JavaScriptCore

class JSCWorker {
    var context:JSContext;
    var EXOKIT:JSValue;
    var _backing:WorkerBacking;
    
    fileprivate var requireUtil : Require? = nil
    
    init(_ path:String, backing: WorkerBacking) {
        _backing = backing;
        
        context = JSContext()
        context.exceptionHandler = { context, exception in
            if let exc = exception {
                print("!!!!! THREAD Exception", exc.toString())
            }
        }
        
        let log: @convention(block) (String) -> Void = { string in
            print(string);
        }
        context.setObject(unsafeBitCast(log, to: AnyObject.self), forKeyedSubscript: "print" as NSString)
        context.globalObject.setValue(backing.index, forProperty: "THREAD_INDEX");
        
        context.evaluateScript(Utils.loadInternalJS(name: "engine"));
        EXOKIT = context.objectForKeyedSubscript("EXOKIT");
        requireUtil = Require()
        let requireCallback: @convention(block) (String) -> AnyObject = { input in
            if let requiredModule = self.requireUtil {
                if let ret = requiredModule.require(uri: input) {
                    return ret
                }
            }
            
            return JSValue(undefinedIn: self.context)
        }
        context.setObject(unsafeBitCast(requireCallback, to: AnyObject.self), forKeyedSubscript: "require" as NSString)
        
        print("Initialized JSCWorker in thread");
        requireUtil?.setResolve(resource: "exokitjs/core", ofType: "")
        let exokitjsCorePath = requireUtil?.currentRequireContext() ?? ""
        if let jstxt = try? String(contentsOfFile: "\(exokitjsCorePath)/worker-thread.js") {
            context.evaluateScript(jstxt)
        }
        
        context.setObject(File.self, forKeyedSubscript: "File" as NSString)

        initCommunication();
        
        EXOKIT.setObject(Bundle.main.infoDictionary!["EXOKIT_URL"] as! String, forKeyedSubscript: "rootPath" as NSString)
        let initFn = EXOKIT.objectForKeyedSubscript("init");
        let _ = initFn?.call(withArguments: [path]);
    }
    
    fileprivate func initCommunication() {
        let evaluate: @convention(block) (String) -> Void = { code in
            self.context.evaluateScript(code);
        }
        EXOKIT.setObject(unsafeBitCast(evaluate, to: AnyObject.self), forKeyedSubscript: "evaluate" as NSString)
        
        let postMessage: @convention(block) (String) -> Void = { msg in
            self._backing.receiveMessage(msg);
        }
        EXOKIT.setObject(unsafeBitCast(postMessage, to: AnyObject.self), forKeyedSubscript: "postMessage" as NSString)
        
        let transferData: @convention(block) (String, [Double]) -> Void = { key, array in
            let aura = JSCEngine.jsContext?.objectForKeyedSubscript("EXOKIT");
            let cb = aura?.objectForKeyedSubscript("receiveTransfer");
            let _ = cb?.call(withArguments: [key, array])
        }
        EXOKIT.setObject(unsafeBitCast(transferData, to: AnyObject.self), forKeyedSubscript: "transferData" as NSString)
    }
    
    func postMessage(_ string:String) {
        let cb = EXOKIT.objectForKeyedSubscript("onMessage");
        let _ = cb?.call(withArguments: [string])
    }
    
    func tick() {
        let cb = EXOKIT.objectForKeyedSubscript("tick");
        let _ = cb?.call(withArguments: nil)
    }
    
    func terminate() {
        
    }
}