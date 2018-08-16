import Foundation
import Kitura
import LoggerAPI
import Configuration
import CloudEnvironment
import KituraContracts
import Health
import KituraStencil
import Stencil
import FileKit

public let projectPath = ConfigurationManager.BasePath.project.path
public let health = Health()

public class App {
    let router = Router()
    let cloudEnv = CloudEnv()

    public init() throws {
        // Run the metrics initializer
        initializeMetrics(router: router)
    }

    func postInit() throws {
        // Endpoints
        initializeHealthRoutes(app: self)
        // Configures Stencil.
        let stencil = Extension()
let fileURL = FileKit.projectFolderURL.appendingPathComponent("payload.json")
var content: String!
do {
  content = try String(contentsOf: fileURL, encoding: .utf8)
} catch {
  fatalError(error.localizedDescription)
}
let data = Data(content.utf8)
print("Creating context")
let context: [String:Any] = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any] ?? ["It's":"Broken"]
print("Context done")
        StencilFilters.register(on: stencil)
router.setDefault(templateEngine: StencilTemplateEngine(extension: stencil))
router.get("/banana") {
request, response, next in
try response.render("template", context: context).end()
}
    }

    public func run() throws {
        try postInit()
        Kitura.addHTTPServer(onPort: cloudEnv.port, with: router)
        Kitura.run()
    }
}
