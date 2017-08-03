import Credentials
import Foundation
import Kitura
import KituraSession
import KituraStencil
import LoggerAPI

/*
 Handles the web front-end.
 Requires BaseContextMiddleware and LocationMiddleware.
 */
func configureWebRouter(using router: Router) {

    router.get("/home") {
        request, response, next in
        try response.render("\(Settings.locale)/home", context: request.userInfo)
        next()
    }
    
    /*
     Provides a selection of new games, upcoming games and games near the user.
     */
    router.get("/games") {
        request, response, next in
        guard let coordinates = request.userInfo["coordinates"] as? [String: Any],
              let latitude = coordinates["latitude"] as? Double,
              let longitude = coordinates["longitude"] as? Double else {
            try logAndThrow(ServerError.missingMiddleware(type: LocationMiddleware.self))
        }
        let location = Location(latitude: latitude, longitude: longitude)
        let newestGames = try GameRepository().newestGames(withDistanceMeasuredFrom: location, limitedTo: 4)
        let upcomingGames = try GameRepository().upcomingGames(withDistanceMeasuredFrom: location, limitedTo: 4)
        let gamesNearMe = try GameRepository().gamesNearMe(withDistanceMeasuredFrom: location, limitedTo: 4)
        try response.render("\(Settings.locale)/games", context: try GamesViewContext(
            base: request.userInfo,
            newest: newestGames,
            upcoming: upcomingGames,
            nearMe: gamesNearMe
        ))
        next()
    }
    
    /*
     Full list of games, sorted by date of creation.
     */
    router.get("/newest-games") {
        request, response, next in
        guard let pageString = request.queryParameters["page"],
              let page = Int(pageString) else {
            try logAndThrow(ServerError.invalidRequest)
        }
        guard let coordinates = request.userInfo["coordinates"] as? [String: Any],
              let latitude = coordinates["latitude"] as? Double,
              let longitude = coordinates["longitude"] as? Double else {
            try logAndThrow(ServerError.missingMiddleware(type: LocationMiddleware.self))
        }
        let location = Location(latitude: latitude, longitude: longitude)
        let pageSize = 8
        let games = try GameRepository().newestGames(withDistanceMeasuredFrom: location, startingFrom: page * pageSize, limitedTo: pageSize)
        let remainingGames = try GameRepository().availableGamesCount() - (page + 1) * pageSize
        try response.render("\(Settings.locale)/games-page", context: try GamesPageViewContext(
            base: request.userInfo,
            type: .newest,
            games: games,
            page: page,
            hasNextPage: remainingGames > 0
        ))
        next()
    }
    
    /*
     Full list of games, sorted by date.
     */
    router.get("/upcoming-games") {
        request, response, next in
        guard let pageString = request.queryParameters["page"],
              let page = Int(pageString) else {
            try logAndThrow(ServerError.invalidRequest)
        }
        guard let coordinates = request.userInfo["coordinates"] as? [String: Any],
              let latitude = coordinates["latitude"] as? Double,
              let longitude = coordinates["longitude"] as? Double else {
            try logAndThrow(ServerError.missingMiddleware(type: LocationMiddleware.self))
        }
        let location = Location(latitude: latitude, longitude: longitude)
        let pageSize = 8
        let games = try GameRepository().upcomingGames(withDistanceMeasuredFrom: location, startingFrom: page * pageSize, limitedTo: pageSize)
        let remainingGames = try GameRepository().availableGamesCount() - (page + 1) * pageSize
        try response.render("\(Settings.locale)/games-page", context: try GamesPageViewContext(
            base: request.userInfo,
            type: .upcoming,
            games: games,
            page: page,
            hasNextPage: remainingGames > 0
        ))
        next()
    }
    
    /*
     Full list of games, sorted by the distance to the user.
     */
    router.get("/games-near-me") {
        request, response, next in
        guard let pageString = request.queryParameters["page"],
              let page = Int(pageString) else {
            try logAndThrow(ServerError.invalidRequest)
        }
        guard let coordinates = request.userInfo["coordinates"] as? [String: Any],
              let latitude = coordinates["latitude"] as? Double,
              let longitude = coordinates["longitude"] as? Double else {
            try logAndThrow(ServerError.missingMiddleware(type: LocationMiddleware.self))
        }
        let location = Location(latitude: latitude, longitude: longitude)
        let pageSize = 8
        let games = try GameRepository().gamesNearMe(withDistanceMeasuredFrom: location, startingFrom: page * pageSize, limitedTo: pageSize)
        let remainingGames = try GameRepository().availableGamesCount() - (page + 1) * pageSize
        try response.render("\(Settings.locale)/games-page", context: try GamesPageViewContext(
            base: request.userInfo,
            type: .nearMe,
            games: games,
            page: page,
            hasNextPage: remainingGames > 0
        ))
        next()
    }
    
    /*
     Host a game or activity.
     */
    router.get("/host") {
        request, response, next in
        try response.render("\(Settings.locale)/host", context: request.userInfo)
        next()
    }
    
    /*
     When searching for a game to host, the user is presented with this selection page.
     */
    router.get("/host-game-select") {
        request, response, next in
        guard let query = request.queryParameters["query"],
              query.characters.count > 0 else {
            try logAndThrow(ServerError.invalidRequest)
        }
        let results = try GameDataRepository().searchResults(forQuery: query, exactMatchesOnly: request.queryParameters["exact"] == "on")
        guard results.count > 0 else {
            try response.render("\(Settings.locale)/host", context: request.userInfo.appending([
                "query": query,
                "error": true
            ]))
            next()
            return
        }
        try response.render("\(Settings.locale)/host-game-select", context: HostGameSelectViewContext(
            base: request.userInfo,
            results: results
        ))
        next()
    }
    
    /*
     After selecting a game to host, the user is presented with this form.
     */
    router.get("/host-game") {
        request, response, next in
        guard let idString = request.queryParameters["id"],
              let id = Int(idString),
              let gameData = try GameDataRepository().gameData(forID: id) else {
            try logAndThrow(ServerError.invalidRequest)
        }
        try response.render("\(Settings.locale)/host-game", context: HostGameViewContext(
            base: request.userInfo,
            game: gameData
        ))
        next()
    }
    
    /*
     Validates the form submitted to host a game.
     */
    router.post("/host-game", middleware: BodyParser())
    router.post("/host-game") {
        request, response, next in
        guard let body = request.body?.asURLEncoded,
              let idString = body["id"], let id = Int(idString),
              let name = body["name"],
              let playerCountString = body["playerCount"], let playerCount = Int(playerCountString),
              let minPlayerCountString = body["minPlayerCount"], let minPlayerCount = Int(minPlayerCountString),
              let prereservedSeatsString = body["prereservedSeats"], let prereservedSeats = Int(prereservedSeatsString),
              let dayString = body["day"], let day = Int(dayString),
              let monthString = body["month"], let month = Int(monthString),
              let yearString = body["year"], let year = Int(yearString),
              let hourString = body["hour"], let hour = Int(hourString),
              let minuteString = body["minute"], let minute = Int(minuteString),
              let deadlineType = body["deadline"],
              let address = body["address"], address.characters.count > 0,
              let city = body["city"], city.characters.count > 0,
              let latitudeString = body["latitude"], let latitude = Double(latitudeString),
              let longitudeString = body["longitude"], let longitude = Double(longitudeString),
              let info = body["info"] else {
            try logAndThrow(ServerError.invalidRequest)
        }
        // Make sure the ID is valid.
        guard var data = try GameDataRepository().gameData(forID: id) else {
            try logAndThrow(ServerError.invalidRequest)
        }
        // Make sure the name is valid for the selected game.
        guard let names = data.names, names.contains(name) else {
            try logAndThrow(ServerError.invalidRequest)
        }
        // Update the game data to use the selected name.
        data.name = name
        data.names = nil
        // Make sure the player counts are valid for the selected game.
        guard data.playerCount.contains(playerCount),
              data.playerCount.contains(minPlayerCount),
              minPlayerCount <= playerCount else {
            try logAndThrow(ServerError.invalidRequest)
        }
        // Update the game data to use the selected player counts.
        data.playerCount = minPlayerCount...playerCount
        // Make sure the number of prereserved seats makes sense for the selected player count.
        // There should also be at least one seat left.
        guard (0..<playerCount).contains(prereservedSeats) else {
            try logAndThrow(ServerError.invalidRequest)
        }
        // Make sure the date is valid and in the future.
        let calendar = Calendar(identifier: .gregorian)
        var dateComponents = DateComponents()
        dateComponents.calendar = calendar
        dateComponents.day = day
        dateComponents.month = month
        dateComponents.year = year
        dateComponents.hour = hour
        dateComponents.minute = minute
        dateComponents.timeZone = Settings.timeZone
        guard dateComponents.isValidDate,
              let date = dateComponents.date,
              date.compare(Date()) == .orderedDescending else {
            try logAndThrow(ServerError.invalidRequest)
        }
        // Calculate the deadline and make sure it is in the future.
        let deadline: Date
        switch deadlineType {
        case "one hour":
            deadline = calendar.date(byAdding: .hour, value: -1, to: date)!
        case "one day":
            deadline = calendar.date(byAdding: .day, value: -1, to: date)!
        case "two days":
            deadline = calendar.date(byAdding: .day, value: -2, to: date)!
        case "one week":
            deadline = calendar.date(byAdding: .weekOfYear, value: -1, to: date)!
        default:
            try logAndThrow(ServerError.invalidRequest)
        }
        guard deadline.compare(Date()) == .orderedDescending else {
            try logAndThrow(ServerError.invalidRequest)
        }
        guard let hostID = request.userProfile?.id else {
            try logAndThrow(ServerError.missingMiddleware(type: Credentials.self))
        }
        guard let host = try UserRepository().user(withID: hostID) else {
            try logAndThrow(ServerError.missingMiddleware(type: AuthenticationMiddleware.self))
        }
        let game = Game(host: host,
                        prereservedSeats: prereservedSeats,
                        data: data,
                        date: date,
                        deadline: deadline,
                        location: Location(address: address, city: city, latitude: latitude, longitude: longitude),
                        info: info.trimmingCharacters(in: .whitespacesAndNewlines))
        try GameRepository().add(game)
        guard let gameID = game.id else {
            try logAndThrow(ServerError.invalidState)
        }
        guard let session = request.session else {
            try logAndThrow(ServerError.missingMiddleware(type: Session.self))
        }
        guard let token = session["facebookAccessToken"].string else {
            try logAndThrow(ServerError.missingMiddleware(type: AuthenticationMiddleware.self))
        }
        try FacebookService(accessToken: token).accounce(game)
        try response.redirect("/web/game/\(gameID)")
        next()
    }
    
    /*
     Gives detailed information about a game, including its approved and waiting requests.
     */
    router.get("/game/:id") {
        request, response, next in
        guard let userID = request.userProfile?.id else {
            try logAndThrow(ServerError.missingMiddleware(type: Credentials.self))
        }
        guard let user = try UserRepository().user(withID: userID) else {
            try logAndThrow(ServerError.missingMiddleware(type: AuthenticationMiddleware.self))
        }
        guard let coordinates = request.userInfo["coordinates"] as? [String: Any],
              let latitude = coordinates["latitude"] as? Double,
              let longitude = coordinates["longitude"] as? Double else {
            try logAndThrow(ServerError.missingMiddleware(type: LocationMiddleware.self))
        }
        let location = Location(latitude: latitude, longitude: longitude)
        guard let id = request.parameters["id"],
              let game = try GameRepository().game(withID: id, withDistanceMeasuredFrom: location),
              game.date.compare(Date()) == .orderedDescending,
              !game.cancelled else {
            try logAndThrow(ServerError.invalidRequest)
        }
        let requests = try RequestRepository().requests(for: game)
        try response.render("\(Settings.locale)/game", context: try GameViewContext(
            base: request.userInfo,
            user: user,
            game: game,
            requests: requests
        ))
        next()
    }
    
    /*
     Cancel a game.
     */
    router.post("/game/:id", middleware: BodyParser())
    router.post("/game/:id") {
        request, response, next in
        guard let userID = request.userProfile?.id else {
            try logAndThrow(ServerError.missingMiddleware(type: Credentials.self))
        }
        guard let user = try UserRepository().user(withID: userID) else {
            try logAndThrow(ServerError.missingMiddleware(type: AuthenticationMiddleware.self))
        }
        guard let gameID = request.parameters["id"],
              let game = try GameRepository().game(withID: gameID),
              game.date.compare(Date()) == .orderedDescending,
              let body = request.body?.asURLEncoded else {
            try logAndThrow(ServerError.invalidRequest)
        }
        if let cancelled = body["cancelled"], cancelled == "on", user == game.host {
            try GameRepository().cancel(game)
            for player in try UserRepository().players(for: game) {
                try MessageRepository().add(Message(category: .hostCancelledGame(game), recipient: player))
            }
        } else {
            try logAndThrow(ServerError.invalidRequest)
        }
        try response.redirect("/web/home")
        next()
    }
    
    /*
     Submit a request to join a game.
     */
    router.post("/requests", middleware: BodyParser())
    router.post("/requests") {
        routerRequest, routerResponse, next in
        guard let body = routerRequest.body?.asURLEncoded,
              let gameID = body["game"],
              let game = try GameRepository().game(withID: gameID),
              game.deadline.compare(Date()) == .orderedDescending,
              !game.cancelled,
              let seatsString = body["seats"],
              let seats = Int(seatsString),
              seats >= 1 && seats <= game.availableSeats else {
            try logAndThrow(ServerError.invalidRequest)
        }
        guard let userID = routerRequest.userProfile?.id else {
            try logAndThrow(ServerError.missingMiddleware(type: Credentials.self))
        }
        guard let user = try UserRepository().user(withID: userID) else {
            try logAndThrow(ServerError.missingMiddleware(type: AuthenticationMiddleware.self))
        }
        let request = Request(player: user, game: game, seats: seats)
        try RequestRepository().add(request)
        try MessageRepository().add(Message(category: .requestReceived(request), recipient: game.host))
        try routerResponse.redirect("/web/game/\(gameID)")
        next()
    }
    
    /*
     Approve or cancel a request.
     */
    router.post("/request/:id", middleware: BodyParser())
    router.post("/request/:id") {
        routerRequest, routerResponse, next in
        guard let userID = routerRequest.userProfile?.id else {
            try logAndThrow(ServerError.missingMiddleware(type: Credentials.self))
        }
        guard let user = try UserRepository().user(withID: userID) else {
            try logAndThrow(ServerError.missingMiddleware(type: AuthenticationMiddleware.self))
        }
        guard let requestID = routerRequest.parameters["id"],
              let request = try RequestRepository().request(withID: requestID),
              request.game.date.compare(Date()) == .orderedDescending,
              !request.game.cancelled,
              let body = routerRequest.body?.asURLEncoded else {
            try logAndThrow(ServerError.invalidRequest)
        }
        if let approved = body["approved"], approved == "on", user == request.game.host {
            try RequestRepository().approve(request)
            try MessageRepository().add(Message(category: .requestApproved(request), recipient: request.player))
        } else if let cancelled = body["cancelled"], cancelled == "on", user == request.player || user == request.game.host {
            try RequestRepository().cancel(request)
            if user == request.game.host {
                try MessageRepository().add(Message(category: .hostCancelledRequest(request), recipient: request.player))
            } else {
                try MessageRepository().add(Message(category: .playerCancelledRequest(request), recipient: request.game.host))
            }
        } else {
            try logAndThrow(ServerError.invalidRequest)
        }
        guard let gameID = request.game.id else {
            try logAndThrow(ServerError.invalidState)
        }
        try routerResponse.redirect("/web/game/\(gameID)")
        next()
    }
    
    /*
     Shows an overview of the games the user is hosting and the games the user is playing.
     */
    router.get("my-games") {
        request, response, next in
        guard let userID = request.userProfile?.id else {
            try logAndThrow(ServerError.missingMiddleware(type: Credentials.self))
        }
        guard let user = try UserRepository().user(withID: userID) else {
            try logAndThrow(ServerError.missingMiddleware(type: AuthenticationMiddleware.self))
        }
        guard let coordinates = request.userInfo["coordinates"] as? [String: Any],
              let latitude = coordinates["latitude"] as? Double,
              let longitude = coordinates["longitude"] as? Double else {
            try logAndThrow(ServerError.missingMiddleware(type: LocationMiddleware.self))
        }
        let location = Location(latitude: latitude, longitude: longitude)
        let hostedGames = try GameRepository().games(hostedBy: user)
        let playingGames = try GameRepository().games(joinedBy: user, withDistanceMeasuredFrom: location)
        try response.render("\(Settings.locale)/my-games", context: try MyGamesViewContext(
            base: request.userInfo,
            hosted: hostedGames,
            playing: playingGames
        ))
        next()
    }
    
    router.get("messages") {
        request, response, next in
        guard let userID = request.userProfile?.id else {
            try logAndThrow(ServerError.missingMiddleware(type: Credentials.self))
        }
        guard let user = try UserRepository().user(withID: userID) else {
            try logAndThrow(ServerError.missingMiddleware(type: AuthenticationMiddleware.self))
        }
        let messages = try MessageRepository().messages(for: user)
        try response.render("\(Settings.locale)/messages", context: try MessagesViewContext(
            base: request.userInfo,
            messages: messages
        ))
        try MessageRepository().markAsRead(messages)
        next()
    }
}
