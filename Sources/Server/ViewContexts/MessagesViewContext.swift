import Foundation

/*
 View context for `messages.stencil`.
 */
struct MessagesViewContext: ViewContext {
    
    let base: [String: Any]
    var contents: [String: Any] = [:]
    
    init(base: [String: Any], messages: [Message]) throws {
        self.base = base
        contents = [
            "messages": try messages.map(messageMapper)
        ]
    }
    
    private func messageMapper(_ message: Message) throws -> [String: Any] {
        var output: [String: Any] = [
            "creationDate": message.creationDate.formatted(dateStyle: .long, timeStyle: .short),
            "category": message.category.description,
            "read": message.read
        ]
        switch message.category {
        case .hostCancelledGame(let game):
            output["sender"] = [
                "name": game.host.name,
                "picture": game.host.picture?.absoluteString ?? Settings.defaultProfilePicture
            ]
            output["game"] = [
                "name": game.data.name,
                "date": game.date.formatted(dateStyle: .full)
            ]
        case .requestReceived(let request), .playerCancelledRequest(let request):
            guard let gameID = request.game.id else {
                try logAndThrow(ServerError.invalidState)
            }
            output["link"] = "/web/game/\(gameID)"
            output["sender"] = [
                "name": request.player.name,
                "picture": request.player.picture?.absoluteString ?? Settings.defaultProfilePicture
            ]
            output["game"] = [
                "name": request.game.data.name,
                "date": request.game.date.formatted(dateStyle: .full)
            ]
        case .requestApproved(let request), .hostCancelledRequest(let request):
            guard let gameID = request.game.id else {
                try logAndThrow(ServerError.invalidState)
            }
            output["link"] = "/web/game/\(gameID)"
            output["sender"] = [
                "name": request.game.host.name,
                "picture": request.game.host.picture?.absoluteString ?? Settings.defaultProfilePicture
            ]
            output["game"] = [
                "name": request.game.data.name,
                "date": request.game.date.formatted(dateStyle: .full)
            ]
        }
        return output
    }
}
