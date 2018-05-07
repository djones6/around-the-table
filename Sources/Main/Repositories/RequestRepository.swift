import MongoKitten

struct RequestRepository {
    
    func add(_ request: Request) throws {
        guard request.id == nil else {
            try logAndThrow(ServerError.persistedEntity)
        }
        guard let gameID = request.game.id else {
            try logAndThrow(ServerError.unpersistedEntity)
        }
        // Only one request per game per player (not including cancelled requests) is allowed.
        guard try collection(.requests).count(["game": gameID, "player": request.player.id, "cancelled": false], limitedTo: 1) == 0 else {
            try logAndThrow(ServerError.invalidState)
        }
        guard let newID = try collection(.requests).insert(request.toBSON()) as? ObjectId else {
            try logAndThrow(BSONError.missingField(name: "_id"))
        }
        request.id = newID.hexString
    }
    
    func request(withID id: String) throws -> Request? {
        return try collection(.requests).findOne(["_id": ObjectId(id)]).map { try Request(bson: $0) }
    }
    
    func requests(`for` game: Game) throws -> [Request] {
        guard let id = game.id else {
            try logAndThrow(ServerError.unpersistedEntity)
        }
        return try collection(.requests).find(["game": id, "cancelled": false], sortedBy: ["creationDate": .descending]).map { try Request(bson: $0) }
    }
    
    func unapprovedRequestCount(`for` game: Game) throws -> Int {
        guard let id = game.id else {
            try logAndThrow(ServerError.unpersistedEntity)
        }
        return try collection(.requests).count(["game": id, "approved": false, "cancelled": false])
    }
    
    /*
     May return a number smaller than 0 if the game is overbooked.
     */
    func approvedSeats(`for` game: Game) throws -> Int {
        guard let id = game.id else {
            try logAndThrow(ServerError.unpersistedEntity)
        }
        let results = try collection(.requests).aggregate([
            .match([
                "game": id,
                "approved": true,
                "cancelled": false
            ] as Query),
            .group("", computed: ["approvedSeats": .sumOf("$seats")])
        ])
        if let result = results.next(),
           let approvedSeats = Int(result["approvedSeats"]) {
            return approvedSeats
        } else {
            return 0
        }
    }
    
    func approve(_ request: Request) throws {
        guard let id = request.id,
              let gameID = request.game.id else {
            try logAndThrow(ServerError.unpersistedEntity)
        }
        guard !request.cancelled && !request.approved else {
            try logAndThrow(ServerError.invalidState)
        }
        request.approved = true
        try collection(.requests).update(["_id": try ObjectId(id)], to: ["$set": ["approved": true]])
        request.game.availableSeats = max(request.game.availableSeats - request.seats, 0)
        try collection(.games).update(["_id": try ObjectId(gameID)], to: ["$set": ["availableSeats": request.game.availableSeats]])
    }
    
    func cancel(_ request: Request) throws {
        guard let id = request.id,
              let gameID = request.game.id else {
            try logAndThrow(ServerError.unpersistedEntity)
        }
        guard !request.cancelled else {
            try logAndThrow(ServerError.invalidState)
        }
        request.cancelled = true
        try collection(.requests).update(["_id": try ObjectId(id)], to: ["$set": ["cancelled": true]])
        request.game.availableSeats = try max(request.game.data.playerCount.upperBound - request.game.prereservedSeats - approvedSeats(for: request.game), 0)
        try collection(.games).update(["_id": try ObjectId(gameID)], to: ["$set": ["availableSeats": request.game.availableSeats]])
    }
}
