import Foundation
import Kitura
import LoggerAPI
import HeliumLogger
import Application

do {

    HeliumLogger.use(LoggerMessageType.info)

    let app = try App()
    try app.run()

} catch let error {
print(error)
    Log.error(error.localizedDescription)
}
